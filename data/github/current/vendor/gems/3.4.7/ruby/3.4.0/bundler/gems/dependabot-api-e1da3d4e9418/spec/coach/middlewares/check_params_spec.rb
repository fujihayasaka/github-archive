# frozen_string_literal: true

require "rails_helper"

RSpec.describe Middlewares::CheckParams do
  subject(:instance) { described_class.new(context, null_middleware, config) }

  let(:context) do
    { request: instance_double(ActionDispatch::Request, params: params) }
  end

  context "with a required param" do
    let(:config) { { some_param: { required: true } } }

    context "that is missing" do
      let(:params) { { some_other_param: "123" } }

      it { is_expected.to respond_with_status(400) }
      it { is_expected.to respond_with_body_that_matches(/Missing/) }
    end

    context "that is present" do
      let(:params) { { some_param: "123" } }

      it { is_expected.to call_next_middleware }
    end

    context "that is false" do
      let(:params) { { some_param: false } }

      it { is_expected.to call_next_middleware }
    end

    context "that is nested" do
      let(:params) { { some_param: { the_param: "123" } } }
      let(:config) { { "some_param.the_param" => { required: true } } }

      it { is_expected.to call_next_middleware }
    end
  end

  context "with a specified type" do
    let(:config) { { some_param: { type: String } } }

    context "that matches" do
      let(:params) { { some_param: "hello" } }

      it { is_expected.to call_next_middleware }
    end

    context "that doesn't match" do
      let(:params) { { some_param: 123 } }

      it { is_expected.to respond_with_status(400) }
      it { is_expected.to respond_with_body_that_matches(/type/) }

      context "because it's nil" do
        let(:params) { { some_param: nil } }

        it { is_expected.to respond_with_status(400) }
        it { is_expected.to respond_with_body_that_matches(/type/) }
      end

      context "because it's omitted" do
        let(:params) { {} }

        it { is_expected.to call_next_middleware }
      end
    end

    context "that is one of an array of specified types" do
      let(:config) { { some_param: { type: [String, Integer] } } }
      let(:params) { { some_param: 123 } }

      it { is_expected.to call_next_middleware }
    end

    context "that is nested" do
      let(:config) { { "some_param.the_param" => { type: String } } }

      context "that matches" do
        let(:params) { { some_param: { the_param: "123" } } }

        it { is_expected.to call_next_middleware }
      end

      context "that doesn't match" do
        let(:params) { { some_param: { the_param: 123 } } }

        it { is_expected.to respond_with_status(400) }
        it { is_expected.to respond_with_body_that_matches(/is of type Int/) }

        context "because it's nil" do
          let(:params) { { some_param: { the_param: nil } } }

          it { is_expected.to respond_with_status(400) }
          it { is_expected.to respond_with_body_that_matches(/type/) }
        end

        context "because it's omitted" do
          let(:params) { { some_param: { another_param: 123 } } }

          it { is_expected.to call_next_middleware }
        end
      end
    end
  end
end
