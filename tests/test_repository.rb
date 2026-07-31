#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "pathname"
require "json"
require "time"
require "uri"
require "yaml"

ROOT = Pathname(__dir__).parent

def assert(condition, message)
  abort("FAIL: #{message}") unless condition
end

skills = %w[check-pr cli-review rabbitloop]
required_sections = ["Prerequisites", "Inputs and options", "Workflow", "Safety", "Stopping", "Failure", "Final report"]

listed, stderr, status = Open3.capture3("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", chdir: ROOT.to_s)
assert(status.success?, "cannot list repository files: #{stderr}")
text_files = listed.split("\0").filter_map do |relative|
  path = ROOT / relative
  next unless path.file?

  body = path.binread
  next if body.include?("\0")

  body.force_encoding("UTF-8")
  next unless body.valid_encoding?

  [path, body]
end

skills.each do |name|
  path = ROOT / name / "SKILL.md"
  assert(path.file?, "missing #{path.relative_path_from(ROOT)}")
  body = path.read
  frontmatter = body.match(/\A---\n(.*?)\n---\n/m)&.captures&.first
  assert(frontmatter, "missing frontmatter in #{name}/SKILL.md")
  assert(YAML.safe_load(frontmatter)["name"] == name, "frontmatter name mismatch for #{name}")
  required_sections.each { |section| assert(body.match?(/^##+ .*#{Regexp.escape(section)}/i), "#{name} lacks #{section} section") }
end

assert(!(ROOT / ("grep" + "loop")).exist?, "legacy skill directory still exists")

reference = ROOT / "docs" / "coderabbit-command-reference.md"
assert(reference.file?, "missing CodeRabbit command reference")
reference_body = reference.read

local_commands = [
  "cr auth login", "cr auth logout", "cr auth status", "cr auth org",
  "cr review", "cr review findings", "cr stats", "cr update", "cr feedback",
  "cr config validate", "cr doctor", "cr skills"
]
local_commands.each { |command| assert(reference_body.include?("`#{command}"), "command reference lacks #{command}") }

hosted_commands = [
  "review", "full review", "pause", "resume", "ignore", "summary",
  "generate docstrings", "generate unit tests", "autofix", "autofix stacked pr",
  "resolve merge conflict", "generate sequence diagram", "approve", "resolve", "configuration",
  "generate configuration", "emit path instructions", "help"
]
hosted_commands.each do |command|
  assert(reference_body.include?("`@coderabbitai #{command}`"), "command reference lacks @coderabbitai #{command}")
end

fixture = ROOT / "tests" / "fixtures" / "cr-0.7.1-review.jsonl"
assert(fixture.file?, "missing CLI 0.7.1 JSONL fixture")
fixture_events = fixture.readlines(chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
assert(fixture_events.map { |event| event["type"] } == %w[review_context status heartbeat finding complete], "CLI fixture event contract changed")
context, review_status, heartbeat, finding, complete = fixture_events
assert(context.values_at("reviewType", "currentBranch", "baseBranch") == %w[uncommitted example main], "CLI fixture review context changed")
assert(review_status.values_at("phase", "status") == %w[analyzing reviewing], "CLI fixture status event changed")
assert(heartbeat["status"] == "reviewing", "CLI fixture heartbeat changed")
assert(finding["severity"] == "major" && finding["fileName"] == "example.rb", "CLI fixture finding changed")
assert(finding["codegenInstructions"].is_a?(String) && !finding["codegenInstructions"].empty? && finding["suggestions"].is_a?(Array), "CLI fixture finding payload incomplete")
assert(complete["status"] == "review_completed", "CLI fixture completion status changed")
assert(complete["findings"] == 1 && complete["reviewedFiles"] == ["example.rb"], "CLI fixture completion payload changed")

def hosted_clean_review_complete?(data)
  command_time = Time.iso8601(data.dig("command", "createdAt"))
  reply_time = Time.iso8601(data.dig("reply", "createdAt"))
  check_time = Time.iso8601(data.dig("check", "updated_at"))
  evidence_end = [reply_time, check_time, Time.iso8601(data.dig("summary", "updatedAt"))].max
  head_oid = Regexp.escape(data.fetch("requestedHeadOid"))
  summary = data.dig("summary", "body")

  data.fetch("laterReviewCommands").none? { |item| Time.iso8601(item.fetch("createdAt")).between?(command_time, evidence_end) } &&
    data.dig("reply", "author") == "coderabbitai" && data.dig("reply", "body").match?(/\b(?:Full )?Review finished\./i) && reply_time > command_time &&
    data.dig("check", "context") == "CodeRabbit" && data.dig("check", "state") == "success" && check_time > command_time &&
    data.dig("summary", "author") == "coderabbitai" && Time.iso8601(data.dig("summary", "updatedAt")) > command_time &&
    summary.include?("No actionable comments were generated") && summary.match?(/between [0-9a-f]{40} and #{head_oid}\./)
end

hosted_fixture = JSON.parse((ROOT / "tests" / "fixtures" / "hosted-clean-review.json").read)
assert(hosted_fixture.fetch("formalReviews").empty?, "clean hosted fixture unexpectedly has a formal review")
assert(hosted_clean_review_complete?(hosted_fixture), "complete clean hosted evidence was rejected")
%w[Review review].each do |capitalization|
  data = JSON.parse(JSON.generate(hosted_fixture))
  data["reply"]["body"] = "Action performed: Full #{capitalization} finished."
  assert(hosted_clean_review_complete?(data), "full-review reply capitalization was rejected")
end

negative_cases = {
  "stale reply" => ->(data) { data["reply"]["createdAt"] = "2026-07-31T09:53:53Z" },
  "intervening command" => ->(data) { data["laterReviewCommands"] << { "createdAt" => "2026-07-31T09:54:00Z" } },
  "command before evidence completes" => ->(data) { data["laterReviewCommands"] << { "createdAt" => "2026-07-31T09:54:30Z" } },
  "failed check" => ->(data) { data["check"]["state"] = "FAILURE" },
  "actionable summary" => ->(data) { data["summary"]["body"].sub!("No actionable comments were generated", "Actionable comments were generated") },
  "rate-limited summary" => ->(data) { data["summary"]["body"] = "Review limit reached. We could not start this review. Reviewing commits between 1111111111111111111111111111111111111111 and #{data["requestedHeadOid"]}." },
  "wrong range end" => ->(data) { data["summary"]["body"].sub!(data["requestedHeadOid"], "3333333333333333333333333333333333333333").concat(" Requested head: #{data["requestedHeadOid"]}.") }
}
negative_cases.each do |name, mutate|
  data = JSON.parse(JSON.generate(hosted_fixture))
  mutate.call(data)
  assert(!hosted_clean_review_complete?(data), "clean hosted gate accepted #{name}")
end

rabbitloop_body = (ROOT / "rabbitloop" / "SKILL.md").read
%w[finished success summary].each do |signal|
  assert(rabbitloop_body.include?(signal), "rabbitloop clean-review gate lacks #{signal} evidence")
end
assert(rabbitloop_body.include?("all three"), "rabbitloop does not require the complete clean-review evidence set")
assert(rabbitloop_body.include?("commits/<headRefOid>/status"), "rabbitloop does not fetch current-head commit-status timestamps")

def walk(node, &block)
  case node
  when Hash
    yield node
    node.each_value { |value| walk(value, &block) }
  when Array
    node.each { |value| walk(value, &block) }
  end
end

markdown = text_files.select { |path, _| path.extname == ".md" }
documents = markdown.to_h do |path, _|
  begin
    output, error, pandoc_status = Open3.capture3("pandoc", "--from=gfm", "--to=json", path.to_s)
  rescue Errno::ENOENT
    abort("FAIL: pandoc is required to validate Markdown")
  end
  assert(pandoc_status.success?, "cannot parse #{path.relative_path_from(ROOT)}: #{error}")
  data = { anchors: [], links: [], bash: [] }
  walk(JSON.parse(output)) do |node|
    case node["t"]
    when "Header"
      data[:anchors] << node.dig("c", 1, 0)
    when "Link"
      data[:links] << node.dig("c", 2, 0)
    when "CodeBlock"
      attributes, code = node["c"]
      data[:bash] << code if attributes[1].include?("bash")
    end
  end
  [path.realpath, data]
end

documents.each do |path, data|
  data[:links].each do |link|
    next if link.match?(%r{\A(?:https?://|mailto:)})

    file, fragment = link.split("#", 2)
    relative = Pathname(URI::DEFAULT_PARSER.unescape(file))
    assert(!relative.absolute?, "absolute local link #{path.relative_path_from(ROOT)} -> #{link}")
    target = file.empty? ? path : (path.dirname / relative).cleanpath
    assert(target.exist?, "broken link #{path.relative_path_from(ROOT)} -> #{link}")
    root = ROOT.realpath
    resolved = target.realpath
    assert(resolved == root || resolved.to_s.start_with?("#{root}#{File::SEPARATOR}"), "link escapes repository #{path.relative_path_from(ROOT)} -> #{link}")
    next unless fragment && !fragment.empty?

    target_document = documents[resolved]
    assert(target_document, "fragment targets non-Markdown file #{path.relative_path_from(ROOT)} -> #{link}")
    anchor = URI::DEFAULT_PARSER.unescape(fragment)
    assert(target_document[:anchors].include?(anchor), "missing fragment #{path.relative_path_from(ROOT)} -> #{link}")
  end

  data[:bash].each_with_index do |block, index|
    syntax_input = block.gsub(/<[^>]+>/, "VALUE")
    _, stderr, status = Open3.capture3("bash", "-n", stdin_data: syntax_input)
    assert(status.success?, "invalid Bash example in #{path.relative_path_from(ROOT)} block #{index + 1}: #{stderr}")
  end
end

legacy_product = "grep" + "tile"
legacy_command = "grep" + "loop"
legacy_hits = text_files.flat_map do |path, body|
  body.lines.filter_map.with_index(1) do |line, number|
    [path.relative_path_from(ROOT).to_s, number, line] if line.match?(/#{legacy_product}|#{legacy_command}/i)
  end
end
allowed_legacy_files = ["LICENSE", "README.md"]
assert(legacy_hits.all? { |file, _, _| allowed_legacy_files.include?(file) }, "unexpected legacy reference")
assert(legacy_hits.length == 2, "expected only migration and legal legacy references")

all_text = text_files.map(&:last).join("\n")
home_prefix = "/" + "Users" + "/"
assert(!all_text.match?(Regexp.new(Regexp.escape(home_prefix) + "[^/\\s]+")), "machine-local path found")
credential_patterns = [
  Regexp.new("\\bgh" + "[pousr]_[A-Za-z0-9_]+\\b"),
  Regexp.new("\\bgithub" + "_pat_[A-Za-z0-9_]+\\b"),
  Regexp.new("\\bcr" + "-[A-Za-z0-9]{16,}\\b"),
  Regexp.new("-" * 5 + "BEGIN (?:[A-Z ]+ )?PRIVATE KEY" + "-" * 5)
]
assert(!all_text.match?(Regexp.union(credential_patterns)), "credential-like value found")

puts "repository tests passed"
