# typed: true
# frozen_string_literal: true

require "test_helper"

class ReactPartialRendererTest < GitHub::TestCase
  include DogstatsTestHelpers

  class FakeController < ApplicationController; end

  fixtures do
    @user = create(:user)
  end

  context "#initialize" do
    test "builds embedded_data with the props" do
      renderer = build_renderer(props: { foo: "bar" })

      assert_equal renderer.instance_variable_get(:@embedded_data), { props: { foo: "bar" } }
    end
  end

  context "#render" do
    test "calls SsrRenderer and yields response, embedded_data, and attempted_ssr" do
      response = Alloy::Response.new(status: 200)
      React::SsrRenderer.any_instance.expects(:render).yields(response, true)

      build_renderer(props: { foo: "bar" }).render do |ssr_response, embedded_data, attempted_ssr|
        assert_equal ssr_response, response
        assert_equal embedded_data, { props: { foo: "bar" } }
        assert_equal attempted_ssr, true
      end
    end

    test "calls SsrRenderer and yields response, embedded_data, and attempted_ssr even with errors" do
      response = Alloy::Response.new(status: 413)
      React::SsrRenderer.any_instance.expects(:render).yields(response, false)

      build_renderer(props: { baz: 1 }).render do |ssr_response, embedded_data, attempted_ssr|
        assert_equal ssr_response, response
        assert_equal embedded_data, { props: { baz: 1 } }
        assert_equal attempted_ssr, false
      end
    end
  end

  sig do
    params(
      controller: ApplicationController,
      name: String,
      origin: T.untyped,
      props: T.nilable(T.any(T::Struct, T::Hash[Symbol, T.untyped])),
      request: ActionDispatch::Request,
      ssr_hints: Alloy::SelectiveSsr::Hints,
      disable_ssr: T::Boolean,
      force_ssr: T::Boolean,
      user: T.nilable(User),
    ).returns(React::PartialRenderer)
  end
  def build_renderer(
    controller: FakeController.new,
    name: "test",
    origin: nil,
    props: {},
    request: ActionDispatch::Request.new({}),
    ssr_hints: Alloy::SelectiveSsr::Hints.new,
    disable_ssr: false,
    force_ssr: false,
    user: nil
  )
    controller.request = request

    React::PartialRenderer.new(
      controller: controller,
      name:,
      origin:,
      props:,
      request:,
      ssr_hints:,
      disable_ssr:,
      force_ssr:,
      user:
    )
  end
end
