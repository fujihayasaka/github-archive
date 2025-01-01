# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class GpgSignatureRequestTest < GitHub::TestCase

    fixtures do
      @user = create(:user, login: "user")
      @user.update_gpg_authorization(Configurable::GpgAuthorization::ALL_REPOSITORIES, actor: @user)
      @rando = create(:user, login: "rando")
      @codespace = create(:codespace, owner: @user, environment_data: { state: "Available" })
      @user.emails.create(state: "verified", email: "user-verified@github.com")
      @user.emails.map(&:verify!)
      @user.emails.create(state: "unverified", email: "user-unverified@github.com")

      @author_name, @author_email = User.git_author_info(@user)
      @author = "#{@author_name} <#{@author_email}>"
      @gpg_signing_message_template = <<~END
        tree bc6312
        parent 6dbbfe
        author %{user} <%{email}> 1599572979 -0400
        committer GitHub <noreply@github.com> 1599572979 -0400

        testing x1

        author by someone and <monalisa@github.com>

        Co-authored-by: Codespace Guest <guest@example.com>
      END
      @codespace_token = @user.signed_auth_token(
          scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE,
          expires: 1.day.from_now,
          data: { id: @codespace.id }
      )
    end

    def signing_request(current_user: @user, codespace_token: @codespace_token, message: @gpg_signing_message_template % { user: @author_name, email: @author_email })
      Codespaces::GpgSignatureRequest.new \
        current_user:    current_user,
        message:         message,
        codespace_token: codespace_token
    end

    def assert_signing_request_error(attribute, type, **request_args)
      request = signing_request(**request_args)
      refute request.valid?
      assert request.errors.of_kind?(attribute, type)
    end

    context "constructor", skip_enterprise: true do
      test "coerces nil `codespace_token` and `message` arguments to Strings" do
        sat_stub = stub(user: nil)
        GitHub::Authentication::SignedAuthToken.expects(:verify).with(scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE, token: "").returns(sat_stub)
        request = signing_request(codespace_token: nil, message: nil)
        assert_equal "", request.message
      end
    end

    context "#sign", skip_enterprise: true do
      test "it returns the signed message if the request is valid" do
        assert_match "BEGIN PGP SIGNATURE", signing_request.sign
      end

      test "it returns nil if the request is invalid" do
        refute signing_request(current_user: @rando, codespace_token: @codespace_token).sign
      end
    end

    context "validations", skip_enterprise: true do
      test "GPG Sign All Repos: it requires a valid codespace ID in the token data" do
        token = @user.signed_auth_token(
          scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE,
          expires: 1.day.from_now
        )
        assert_signing_request_error(:codespace, :blank, codespace_token: token)
      end

      test "GPG Sign Selected Repos: it requires a valid codespace ID in the token data" do
        @user.stubs(:gpg_authorization).returns(Configurable::GpgAuthorization::SELECTED_REPOSITORIES)
        token = @user.signed_auth_token(
          scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE,
          expires: 1.day.from_now
        )
        assert_signing_request_error(:codespace, :blank, codespace_token: token)
      end

      test "is invalid if the current_user doesn't match the token user" do
        rando_token = @rando.signed_auth_token(
          scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE,
          expires: 1.day.from_now,
          data: { id: @codespace.id }
        )
        assert_signing_request_error(:current_user, "is not the correct user", codespace_token: rando_token)
      end

      test "is invalid if the current codespace is not running" do
        @codespace.update(environment_data: { state: "Stopped" })
        assert_signing_request_error(:codespace, "must be running")
      end

      test "is valid when the codespace is consuming compute" do
        Vscs::State::CONSUMING_COMPUTE_STATES.each do |state|
          @codespace.update(environment_data: { state: state })
          assert signing_request.valid?
        end
      end

      test "is valid when the codespace is still being created if it's a template codespace that requires git reinit" do
        @codespace.update(environment_data: nil, state: :provisioning, guid: nil)
        assert_signing_request_error(:codespace, "must be running")
        # Pretend we're a codespace that requires a git reinit in the VM (we do a fresh find so we can't just stub the instance here)
        Codespace.any_instance.stubs(:requires_git_reinit?).returns(true)
        assert signing_request.valid?
      end

      test "is invalid if the user has GPG disabled" do
        @user.update_gpg_authorization(Configurable::GpgAuthorization::DISABLED, actor: @user)
        assert_signing_request_error(:current_user, "GPG signing disabled")
      end

      test "spaces allowed in author" do
        message = <<~END
          tree bc6312
          parent 6dbbfe
          author   #{@author_name}    <#{@author_email}> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400

          testing x1

          author by someone and <monalisa@github.com>

          Co-authored-by: Codespace Guest <guest@example.com>
        END

        assert signing_request(message:).valid?
      end

      test "it requires an author in the message" do
        message = <<~END
          tree bc6312
          parent 6dbbfe
          committer GitHub <noreply@github.com> 1599572979 -0400

          testing x1

          Co-authored-by: Codespace Guest <guest@example.com>
        END
        assert_signing_request_error(:author, :blank, message: message)
      end

      test "only allows one author in the message" do
        message = <<~END
          tree bc6312
          parent 6dbbfe
          author #{@author_name} <#{@author_email}> 1599572979 -0400
          author another <another@another.com> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400

          testing x1

          author by someone and <monalisa@github.com>

          Co-authored-by: Codespace Guest <guest@example.com>
        END
        assert_signing_request_error(:author, :blank, message: message)
      end

      test "doesn't miss multi-author with empty and line continuation" do
        message = <<~END
          tree bc6312
          parent 6dbbfe
          author <> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400
          author #{@author_name} <#{@author_email}> 1599572979 -0400
          author hacker
           <hacker@example.com> 1599572979 -0400

          testing x1

          author by someone and <monalisa@github.com>

          Co-authored-by: Codespace Guest <guest@example.com>
        END

        assert_signing_request_error(:author, :multiple, message: message)
      end

      test "doesn't miss multi-author with line continuation" do
        message = <<~END
          tree bc6312
          parent 6dbbfe
          author #{@author_name} <#{@author_email}> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400
          author hacker
           <hacker@example.com> 1599572979 -0400

          testing x1

          author by someone and <monalisa@github.com>

          Co-authored-by: Codespace Guest <guest@example.com>
        END

        assert_signing_request_error(:author, :multiple, message: message)
      end

      test "doesn't support line continuation on author" do
        # While git allows leading space as a line continuation it
        # doesn't use that with author so refuse to sign those.
        message = <<~END
          tree bc6312
          parent 6dbbfe
          author #{@author_name}
           <#{@author_email}> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400

          testing x1

          author by someone and <monalisa@github.com>

          Co-authored-by: Codespace Guest <guest@example.com>
        END
        assert_signing_request_error(:author, :blank, message: message)
      end

      test "considers an author field without a user name to be an empty author" do
        message = <<~END
          tree bc6312
          parent 6dbbfe
          author  <another@another.com> 1599572979 -0400
          author #{@author_name} <#{@author_email}> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400

          testing x1

          author by someone and <monalisa@github.com>

          Co-authored-by: Codespace Guest <guest@example.com>
        END
        assert_signing_request_error(:author, :blank, message: message)
      end

      test "is invalid if we detect any mismatch in the passed versus generated commit header" do
        assert_signing_request_error(:author, :invalid, current_user: @rando, codespace_token: @codespace_token)
      end

      test "is invalid if the message has an unverified user email as the author" do
        assert_signing_request_error(:author, :invalid, message: @gpg_signing_message_template % { user: @author_name, email: "user-unverified@github.com" })
      end

      test "is invalid if the message has an unrelated user email as the author" do
        assert_signing_request_error(:author, :invalid, message: @gpg_signing_message_template % { user: @author_name, email: "not-the-user@github.com" })
      end

      test "is valid if the current_user's secondary verified email is in the commit header" do
        assert signing_request(message: @gpg_signing_message_template % { user: @author_name, email: "user-verified@github.com" }).valid?
      end

      test "is valid if the user has a full name" do
        full_name_user = create(:user, :with_profile)
        email = "full-name-user@github.com"
        full_name_user.update_gpg_authorization(Configurable::GpgAuthorization::ALL_REPOSITORIES, actor: full_name_user)
        codespace = create(:codespace, owner: full_name_user, environment_data: { state: "Available" })
        full_name_user.emails.create(state: "verified", email: email)
        full_name_user.emails.map(&:verify!)
        author_name, _ = User.git_author_info(full_name_user)

        codespace_token = full_name_user.signed_auth_token(
            scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE,
            expires: 1.day.from_now,
            data: { id: codespace.id }
        )
        assert signing_request(current_user: full_name_user, codespace_token: codespace_token, message: @gpg_signing_message_template % { user: author_name, email: email }).valid?
      end

      test "is invalid if the commit header does not contain a `tree`" do
        message = <<~END
          parent 6dbbfe
          author #{@author_name} <user-verified@github.com> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400

          testing x1

          author by someone and <monalisa@github.com>

          Co-authored-by: Codespace Guest <guest@example.com>
        END
        assert_signing_request_error(:tree, :blank, message: message)
      end

      test "is invalid if the only mention of `tree` is in the commit message" do
        signature = <<~END
          parent 6dbbfe
          author #{@author_name} <#{@author_email}> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400

          tree planting is great
        END
        assert_signing_request_error(:tree, :blank, message: message)
      end

      test "is invalid if the body contains a tag line" do
        message = <<~END
          object 04b871796dc0420f8e7561a895b52484b701d51a
          type commit
          tag signedtag

          signed tag

          signed tag message body
        END
        assert_signing_request_error(:message, "contains tag fields", message: message)
      end

      test "is invalid if the body contains a tagger line" do
        message = <<~END
          object 04b871796dc0420f8e7561a895b52484b701d51a
          type commit
          tagger #{@author_name} <#{@author_email}> 1465981006 +0000

          signed tag

          signed tag message body
        END
        assert_signing_request_error(:message, "contains tag fields", message: message)
      end

      test "is valid if mention of `tag` occurs in the commit message body only" do
        signature = <<~END
          tree bc6312
          parent 6dbbfe
          author #{@author_name} <#{@author_email}> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400

          tag @defunkt because they were the last to change this file
        END

        assert signing_request(message: signature).valid?
      end

      test "is valid if mention of `tagger` occurs in the commit message body only" do
        signature = <<~END
          tree bc6312
          parent 6dbbfe
          author #{@author_name} <#{@author_email}> 1599572979 -0400
          committer GitHub <noreply@github.com> 1599572979 -0400

          tagger what even is a tagger anyway
        END

        assert signing_request(message: signature).valid?
      end
    end
  end
end
