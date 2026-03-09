ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  # Transactional tests — each test rolls back DB changes
  self.use_transactional_tests = true
end
