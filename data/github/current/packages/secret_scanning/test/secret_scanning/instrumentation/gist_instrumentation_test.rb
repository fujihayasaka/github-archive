# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Instrumentation
  class GistInstrumentationTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @user = create(:user)
    end

    context "Create gist" do
      test "hydro payload includes Gist scanning TSS feature flags" do
        GitHub.stubs(:hydro_enabled?).returns(true)

        expected_flags = %w[flag1 flag2]
        SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns(expected_flags)

        contents = [
          { name: "file1", value: "text" },
          { name: "file2", value: "another" },
        ]
        gist = GistHelpers.generate(contents: contents, user: @user, description: "description")

        message = {
          feature_flags: expected_flags,
        }

        with_hydro_publisher(GitHub.hydro_publisher) do
          assert_hydro_published_partial(message, schema: "github.v1.GistCreate")
        end
      end
    end

    context "Update gist / backfill" do
      test "hydro payload includes Gist scanning TSS feature flags", skip_enterprise: true do
        expected_flags = %w[flag1 flag2]
        SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns(expected_flags)

        contents = [
          { name: "file1", value: "text" },
          { name: "file2", value: "another" },
        ]
        secret_gist  = GistHelpers.generate(contents: contents, user: @user, description: "description", public: false)
        refute secret_gist.public?

        with_hydro_publisher(GitHub.hydro_publisher) do
          secret_gist.update!(public: true)

          assert secret_gist.public?

          message = {
            feature_flags: expected_flags,
          }

          assert_hydro_published_partial(message, schema: "token_scanning_service.v0.BackfillRequest")
        end
      end
    end
  end
end
