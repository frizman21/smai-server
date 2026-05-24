ENV["RAILS_ENV"] ||= "test"
ENV["OPENAI_API_KEY"] ||= "test-openai-key"
# Default APP_HOST so the invitation send-blocker check (which gates the
# create flow on APP_HOST + mailbox) doesn't trip in tests that aren't
# specifically exercising that path. Tests can override per-block.
ENV["APP_HOST"] ||= "test.example"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/email_helpers"

OmniAuth.config.test_mode = true
OmniAuth.config.logger = Rails.logger

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup do
      GmailSender.reset_deliveries!
      SmsSender.reset_deliveries!
    end

    # Add more helper methods to be used by all tests here...
  end
end
