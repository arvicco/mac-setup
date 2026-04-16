# frozen_string_literal: true

require "rake/testtask"

Dir["tasks/*.rake"].each { |f| load f }

Rake::TestTask.new("test:unit") do |t|
  t.libs << "lib" << "test"
  t.pattern = "test/unit/**/test_*.rb"
end

Rake::TestTask.new("test:integration") do |t|
  t.libs << "lib" << "test"
  t.pattern = "test/integration/**/test_*.rb"
end

task test: ["test:unit"]
task default: :test
