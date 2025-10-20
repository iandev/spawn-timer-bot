ruby "3.4.7"

source 'https://rubygems.org'
git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

gem "rake"
gem "foreman"
gem "dotenv"
gem 'discordrb', github: "shardlab/discordrb", branch: "main"
gem 'discordrb-webhooks'
gem 'chronic'
gem 'chronic_duration'
gem 'dotiw'
gem 'pg'
gem 'sequel'
gem 'activesupport'
gem 'require_all'
gem 'dates_from_string'
gem 'sinatra'

group :development, :test do
  gem 'sqlite3'
  gem 'rspec'
  gem 'timecop'
  gem 'pry'
end

group :test do
  gem 'database_cleaner-sequel'
end

gem "rackup", "~> 2.2"
gem "puma", "~> 7.1"
