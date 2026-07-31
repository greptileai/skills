#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

def assert(condition, message)
  abort("FAIL: #{message}") unless condition
end

def run(*command, chdir: nil)
  options = chdir ? { chdir: chdir } : {}
  Open3.popen3(*command, **options) do |stdin, stdout, stderr, wait_thread|
    stdin.close
    stdout_reader = Thread.new { stdout.read }
    stderr_reader = Thread.new { stderr.read }

    unless wait_thread.join(30)
      begin
        Process.kill("TERM", wait_thread.pid)
      rescue Errno::ESRCH
        nil
      end
      unless wait_thread.join(5)
        begin
          Process.kill("KILL", wait_thread.pid)
        rescue Errno::ESRCH
          nil
        end
      end
      abort("FAIL: timed out: #{command.join(' ')}")
    end

    [stdout_reader.value, stderr_reader.value, wait_thread.value]
  end
end

def run!(*command, chdir: nil)
  stdout, stderr, status = run(*command, chdir: chdir)
  assert(status.success?, "#{command.join(' ')} failed: #{stderr}")
  stdout
end

stdout, _, status = run("cr", "--help")
assert(status.success?, "cr --help failed")
%w[auth review stats update feedback config doctor skills].each do |command|
  assert(stdout.match?(/^  #{command}\b/), "root help lacks #{command}")
end

version, _, version_status = run("cr", "--version")
assert(version_status.success?, "cr --version failed")
assert(version.strip == "0.7.1", "CLI version changed; update the command reference and fixtures")

review_help, _, review_help_status = run("cr", "review", "--help")
assert(review_help_status.success?, "cr review --help failed")
%w[--agent --light --show-prompts --committed --uncommitted --include-untracked --config --base --base-commit --dir --api-key].each do |option|
  assert(review_help.include?(option), "review help lacks #{option}")
end

help_commands = [
  %w[auth login], %w[auth logout], %w[auth status], %w[auth org],
  %w[review], %w[review findings], %w[stats], %w[update], %w[feedback],
  %w[config], %w[config validate], %w[doctor], %w[skills]
]
help_commands.each do |parts|
  _, _, help_status = run("cr", *parts, "--help")
  assert(help_status.success?, "cr #{parts.join(' ')} --help failed")
end

stdout, _, status = run("cr", "auth", "status", "--agent")
assert(status.success?, "authenticated status check failed")
auth = JSON.parse(stdout)
assert(auth["authenticated"] == true, "CodeRabbit CLI is not authenticated")

_, _, status = run("cr", "doctor")
assert(status.success?, "cr doctor failed")

Dir.mktmpdir("rabbitloop-cli-") do |dir|
  run!("git", "init", "-q", chdir: dir)
  run!("git", "config", "user.name", "RabbitLoop Test", chdir: dir)
  run!("git", "config", "user.email", "test@example.invalid", chdir: dir)

  Dir.mktmpdir("rabbitloop-config-") do |config_dir|
    valid = File.join(config_dir, ".coderabbit.yaml")
    invalid = File.join(config_dir, "invalid.yaml")
    File.write(valid, "{}\n")
    File.write(invalid, "language: 123\n")
    _, _, valid_status = run("cr", "config", "validate", valid)
    _, _, invalid_status = run("cr", "config", "validate", invalid)
    _, _, missing_status = run("cr", "config", "validate", File.join(config_dir, "missing.yaml"))
    assert(valid_status.success?, "valid CodeRabbit config rejected")
    assert(!invalid_status.success?, "invalid CodeRabbit config accepted")
    assert(!missing_status.success?, "missing CodeRabbit config accepted")
  end

  File.write(File.join(dir, "README.md"), "# clean\n")
  run!("git", "add", "README.md", chdir: dir)
  run!("git", "commit", "-qm", "init", chdir: dir)
  run!("git", "branch", "-M", "main", chdir: dir)

  stdout, stderr, review_status = run("cr", "review", "--agent", "--dir", dir, "--base", "main")
  assert(review_status.success?, "clean review failed: #{stderr}")
  events = stdout.lines.reject { |line| line.strip.empty? }.map { |line| JSON.parse(line) }
  complete = events.last
  assert(complete && complete["type"] == "complete", "clean review lacks terminal complete event")
  assert(complete["status"] == "review_skipped", "clean review was not skipped")
  assert(complete["findings"] == 0, "clean review reported findings")
end

puts "live CLI tests passed"
