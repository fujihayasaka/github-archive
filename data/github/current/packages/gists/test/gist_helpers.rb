# typed: true
# frozen_string_literal: true

module GistHelpers
  include Rack::Test::Methods

  extend T::Helpers
  requires_ancestor { Minitest::Assertions }

  # Always allow anon gist creation in tests
  def self.generate(options = {})
    GitHub.override(:anonymous_gist_creation_enabled, true) do
      creator = Gist::Creator.new(options.reverse_merge(public: true))
      if creator.create
        creator.gist
      else
        message = "\nCannot create gist with options #{options.inspect}.\nErrors: "
        message << creator.gist.errors.full_messages.to_sentence
        fail message
      end
    end
  end

  def self.generate_deleted(options = {})
    gist = generate(options)
    gist.update(delete_flag: true)
    gist
  end

  def self.generate_with_example_repo(example, options = {})
    # We cannot easily construct a Gist without contents, but here they
    # will be immediately replaced by the contents of an example repository.
    placeholder_contents = [{ name: "placeholder", value: "." }]

    gist = generate(options.reverse_merge(contents: placeholder_contents))
    ExampleRepositories.example_repo example, gist
    gist
  end

  def assert_response(status = 200, msg = nil)
    assert_equal status, last_response.status, msg
    assert_equal "application/json; charset=utf-8", last_response.headers["Content-Type"] unless status == 204
  end
end
