# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create
Minitest::TestTask.create(:test_contract) do |task|
  task.test_globs = ["test/contract/*_contract.rb"]
end

require "rubocop/rake_task"
RuboCop::RakeTask.new

require "yard"
YARD::Rake::YardocTask.new

task default: %i[test test_contract rubocop]
