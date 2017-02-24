require 'slack-ruby-bot'
require_relative 'helpers'
require_relative 'boot'

class DeployBot < SlackRubyBot::Bot
  ENVS = Settings.envs
  APPS = Settings.apps.keys
  MASTER_BRANCH = 'master'.freeze
  EMPTY_CHANGELOG = 'none'.freeze
  DEFAULT_BRANCH = Settings.default_branch || MASTER_BRANCH

  help do
    title 'Deploy Bot'

    desc 'This bot can deploy something to somewhere :)'

    command 'deploy' do
      desc "Command format is: *deploy|накати|задеплой (#{APPS.join('|')})#branch_or_tag to|на (#{ENVS.join('|')})*"
    end

    command 'changelog' do
      desc "Shows changelog against #{MASTER_BRANCH}: *changelog branch*"
    end
  end

  class << self
    private

    def say_error(client, data, text)
      client.say(channel: data.channel, text: ":warning: #{text}") && throw(:exit)
    end
  end

  match(/changelog (?<app>.+)#(?<branch>.+)$/i) do |client, data, match|
    catch(:exit) do
      app = match[:app]
      branch = match[:branch]
      app_base_path = Settings.apps[app.to_sym]

      APPS.include?(app.to_sym)         || say_error(client, data, "Invalid app name `#{app}`, use: #{APPS.join(', ')}")

      git = Utils::Git.new(app_base_path)
      git.fetch_branches                || say_error(client, data, "Cannot fetch repo")
      git.branch_exists?(branch)        || say_error(client, data, "Unknown git branch `#{branch}`")
      git.branch_exists?(MASTER_BRANCH) || say_error(client, data, "Unknown git branch `#{MASTER_BRANCH}`")
      git.sync_branch(branch)           || say_error(client, data, "Couldn't pull `#{branch}`")
      git.sync_branch(MASTER_BRANCH)    || say_error(client, data, "Couldn't pull `#{MASTER_BRANCH}`")

      changelog = git.changelog(branch, against: MASTER_BRANCH).presence || EMPTY_CHANGELOG

      client.say(channel: data.channel, text: "Changelog for `#{branch}`:\n```#{changelog}```")
    end
  end


  match(/(deploy|накати|задеплой) ((?<app>.+)#(?<branch>.+)|(?<app>.+)) (to|на) (?<env>.+)/i) do |client, data, match|
    catch(:exit) do
      app = match[:app]
      branch = match[:branch] || DEFAULT_BRANCH
      env = match[:env]

      client.send(:logger).info "app: #{app}"
      client.send(:logger).info "branch: #{branch}"
      client.send(:logger).info "env: #{env}"

      APPS.include?(app)         || say_error(client, data, "Invalid app name `#{app}`, use: #{APPS.join(', ')}")
      ENVS.include?(env)         || say_error(client, data, "Invalid env `#{env}`, use: #{ENVS.join(', ')}")
      git.fetch_branches         || say_error(client, data, "Cannot fetch branches")
      git.branch_exists?(branch) || say_error(client, data, "Unknown git branch `#{branch}`")
      git.sync_branch(branch)    || say_error(client, data, "Couldn't pull `#{branch}`")

      git.checkout(branch)
      username = client.users[data.user][:name]
      client.send(:logger).info "user: #{username}"
      # client.say(channel: :random, text: "#{username} started deploying #{app}##{branch} to #{env}")
      cmd = "cd #{base_path}; ./deploy.sh"
      client.send(:logger).info "command: #{cmd}"

      Utils::Subprocess.new(cmd) do |stdout, stderr, thread|
        if stdout && !stdout.empty?
          client.send(:logger).info stdout
          client.say(channel: data.channel, text: "Failed: #{stdout}") if stdout =~ /failed\:/
        end

        # if stderr && !stderr.empty?
        # client.send(:logger).error stderr
        # say_error(channel, data, stderr)
        # end
      end
    end
  end

end

SlackRubyBot.configure do |config|
  config.send_gifs = false
end

DeployBot.run
