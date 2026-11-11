# frozen_string_literal: true

RSpec.describe ConsoleAuth do
  it "has a version number" do
    expect(ConsoleAuth::VERSION).not_to be nil
  end

  def fido_login_url(username = "user")
    "https://vault.service.github.net:8200/v1/auth/fido/login/#{username}"
  end

  def stub_fido_request(username, status, headers, body)
    stub_request(:post, fido_login_url(username)).to_return({
      status:  status,
      headers: headers,
      body:    body,
    })
  end

  before do
    allow(ConsoleMonitor).to receive(:install)
  end

  context "gatekeeper" do
    let(:challenge_response) { Struct.new(:token, :url).new("abc123", "https://fido-challenger.fake/challenges/abc123") }

    it "warns and exits if user is not a member of a group with console access" do
      allow(ConsoleAuth).to receive(:login).and_return(["user", []])

      expect(ConsoleAuth).to receive(:warn).with("Sorry, you are not authorized to access the console.\n If you need access please read https://thehub.github.com/security/security-operations/production-shell-access/access/#shell-host-only-gh-console-and-other-miscellaneous-scripts")
      expect { ConsoleAuth.gatekeeper }.to raise_error(SystemExit)
    end

    it "Sets session name when user is a member of group with console access" do
      allow(ConsoleAuth).to receive(:login).and_return(["user", ["ldap-misc-app-gh-console"]])

      ConsoleAuth.gatekeeper
      expect(ConsoleAuth::Session.console_user).to eq("user")
    end
  end

  context "#password_login" do
    def user_pass_stubs
      allow(ConsoleAuth).to receive(:get_username).and_return("user")
      allow(ConsoleAuth).to receive(:get_password).and_return("password")
    end
    
    let(:too_many_attempts_warning) { "Too many failed attempts. All error messages have been recorded to Haystack. If you need assistance, please review https://thehub.github.com/engineering/security/production-shell-access/access/." }
    let(:challenge_response) { Struct.new(:token, :url).new("abc123", "https://fido-challenger.fake/challenges/abc123") }

    it "warns when 0 attempts are remaining" do
      expect(ConsoleAuth).to receive(:warn).with(too_many_attempts_warning)
      ConsoleAuth.password_login(0)
    end

    it "retries when response is false due to error" do
      user_pass_stubs
      allow(ConsoleAuth).to receive(:vault_fido_auth).and_return(false)

      expect(ConsoleAuth).to receive(:prompt)
      expect(ConsoleAuth).to receive(:warn).with(too_many_attempts_warning)
      expect(FIDOChallenger).to receive(:challenge).with("user@github.com", "vault").and_return(challenge_response)

      expect(ConsoleAuth.password_login(1)).to be nil
    end

    it "returns a username and policies upon successful login" do
      user_pass_stubs
      allow(FIDOChallenger).to receive(:challenge).with("user@github.com", "vault").and_return(challenge_response)
      allow(ConsoleAuth).to receive(:prompt)
      stub_fido_request("user", 200, {"Content-Type" => "application/json"}, "{\"auth\" : { \"policies\": [\"ldap-misc-app-gh-console\"] } }")

      expect(ConsoleAuth.password_login).to eq(["user", ["ldap-misc-app-gh-console"]])
    end
  end

  context "vault_fido_auth" do
    it "records an error when a connectivity issue occurs" do
      stub_request(:post, fido_login_url("user")).to_raise(Timeout::Error.new)

      expect(Failbot).to receive(:report) do |e, params|
        expect(e).to be_a ConsoleAuth::ConsoleAuthorizationError
        expect(params[:user]).to eq("user")
      end

      expect(ConsoleAuth).to receive(:warn).twice
      expect(ConsoleAuth.vault_fido_auth("user", "password", "abc123", 1)).to be nil
    end

    it "records an error when response is not 200" do
      stub_fido_request("user", 403, {"Content-Type" => "application/json"}, "{\"errors\" : \"Forbidden, could not authenticate user\"}")

      expect(Failbot).to receive(:report) do |e, params|
        expect(e).to be_a ConsoleAuth::ConsoleAuthorizationError
        expect(params[:user]).to eq("user")
        expect(params[:status]).to eq("403")
      end

      expect(ConsoleAuth).to receive(:warn).twice
      expect(ConsoleAuth.vault_fido_auth("user", "password", "abc123", 1)).to be nil
    end

    it "returns response when code is 200" do
      expected_response = "{\"auth\" : { \"policies\": [\"ldap-misc-app-gh-console\"] } }"
      stub_fido_request("user", 200, {"Content-Type" => "application/json"}, expected_response)

      response = ConsoleAuth.vault_fido_auth("user", "password", "abc123", 1).body

      expect(response).to eq(expected_response)
    end
  end

  context "get_username" do
    let(:username_warning) { "Valid usernames can only contain alphanumeric characters, underscores, and dashes." }

    it "does not accept blank usernames" do
      allow(ConsoleAuth).to receive(:username_input).and_return("")

      expect(ConsoleAuth).to receive(:prompt)
      expect(ConsoleAuth).to receive(:warn).with(username_warning)
      allow(ConsoleAuth).to receive(:gatekeeper)

      ConsoleAuth.get_username(1)
    end

    it "does not accept usernames with non-alphanumeric dash and underscore characters" do
      allow(ConsoleAuth).to receive(:username_input).and_return("user**")

      expect(ConsoleAuth).to receive(:prompt)
      expect(ConsoleAuth).to receive(:warn).with(username_warning)
      allow(ConsoleAuth).to receive(:gatekeeper)

      ConsoleAuth.get_username(1)
    end

    it "exits to gatekeeper if 0 attempts remain" do
      expect(ConsoleAuth).not_to receive(:prompt)
      expect(ConsoleAuth).not_to receive(:warn)
      expect(ConsoleAuth).to receive(:gatekeeper).with(0)

      ConsoleAuth.get_username(0)
    end

    it "returns username when valid" do
      allow(ConsoleAuth).to receive(:username_input).and_return("user_the-cat")
      expect(ConsoleAuth).to receive(:prompt)

      expect(ConsoleAuth.get_username(1)).to eq("user_the-cat")
    end
  end

  def stub_token_request(token, status, headers, body)
    stub_request(:get, "https://vault.service.github.net:8200/v1/auth/token/lookup-self").
      with(headers: {"Authorization" => "Bearer #{token}"}).
      to_return({
        status:  status,
        headers: headers,
        body:    body,
      })
  end

  context "#token_login" do
    it "warns on invalid token" do
      token = "INAVLID"
      stub_token_request(token, 403, {"Content-Type" => "application/json"}, "{\"errors\" : \"Forbidden, could not authenticate user\"}")
      
      expect(ConsoleAuth).to receive(:warn).with("The Vault token in your environment was not accepted. It may have expired.")
      expect(ConsoleAuth).to receive(:warn).with("Forbidden, could not authenticate user")

      expect(ConsoleAuth.token_login(token)).to be_nil
    end

    it "returns a username and policies upon successful login" do
      token = "VALID"
      stub_token_request(token, 200, {"Content-Type" => "application/json"}, "{\"data\" : { \"meta\": { \"username\": \"tokenuser\" }, \"policies\": [\"ldap-misc-app-gh-console\"] } }")

      expect(ConsoleAuth.token_login(token)).to eq(["tokenuser", ["ldap-misc-app-gh-console"]])
    end
  end

  context "#login" do
    context "When env has a VAULT_TOKEN" do
      before do
        ENV["VAULT_TOKEN"] = "MY_TOKEN"
      end

      after do
        ENV.delete("VAULT_TOKEN")
      end

      it "tries token_login" do
        expect(ConsoleAuth).to receive(:token_login).with("MY_TOKEN").and_return(["token_user", ["policy"]])
        expect(ConsoleAuth).not_to receive(:password_login)

        expect(ConsoleAuth.login).to eq ["token_user", ["policy"]]
      end

      it "falls back to password login when token login fails" do
        expect(ConsoleAuth).to receive(:token_login).with("MY_TOKEN").and_return(nil)
        expect(ConsoleAuth).to receive(:password_login).and_return(["password_user", ["password_policy"]])

        expect(ConsoleAuth.login).to eq ["password_user", ["password_policy"]]
      end
    end

    context "When env does not have a VAULT_TOKEN" do
      it "performs password login" do
        expect(ConsoleAuth).not_to receive(:token_login)
        expect(ConsoleAuth).to receive(:password_login).and_return(["password_user", ["password_policy"]])

        expect(ConsoleAuth.login).to eq ["password_user", ["password_policy"]]
      end
    end
  end
end
