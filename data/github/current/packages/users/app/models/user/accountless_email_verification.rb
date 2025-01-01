# typed: strict
# frozen_string_literal: true

class User::AccountlessEmailVerification

  sig { returns(T.nilable(String)) }
  attr_reader :verification_id

  sig { returns(String) }
  attr_reader :display_login

  sig { returns(String) }
  attr_reader :email

  sig { returns(String) }
  attr_reader :verification_token

  sig { returns(T.nilable(Integer)) }
  attr_reader :visitor_id

  sig { returns(T.nilable(SpamuraiFormSignals)) }
  attr_reader :spamurai_form_signals

  sig { returns(T.nilable(String)) }
  attr_reader :funcaptcha_session_id

  sig { returns(T.nilable(T::Boolean)) }
  attr_reader :funcaptcha_solved

  sig { returns(T.nilable(T::Hash[String, String])) }
  attr_reader :funcaptcha_response

  sig { returns(T.nilable(T::Hash[String, String])) }
  attr_reader :funcaptcha_data_exchange

  sig { returns(T.nilable(String)) }
  attr_reader :country_code

  sig { returns(T.nilable(T::Boolean)) }
  attr_reader :explicit_marketing_consent

  sig do
    params(display_login: String, email: String, password_hash: T.nilable(String), verification_token: String,
      verification_id: T.nilable(String), visitor_id: T.nilable(Integer), spamurai_form_signals: T.nilable(SpamuraiFormSignals),
      funcaptcha_session_id: T.nilable(String), funcaptcha_solved: T.nilable(T::Boolean), funcaptcha_response: T.nilable(T::Hash[String, String]),
      funcaptcha_data_exchange: T.nilable(T::Hash[String, String]), country_code: T.nilable(String), explicit_marketing_consent: T.nilable(T::Boolean)
  ).void
  end
  def initialize(display_login:, email:, password_hash:, verification_token:, verification_id: nil, visitor_id: nil, spamurai_form_signals: nil, funcaptcha_session_id: nil, funcaptcha_solved: nil, funcaptcha_response: nil, funcaptcha_data_exchange: nil, country_code: nil, explicit_marketing_consent: false)
    @verification_id = verification_id
    @display_login = display_login
    @email = email
    @password_hash = password_hash
    @verification_token = verification_token
    @visitor_id = visitor_id
    @spamurai_form_signals = spamurai_form_signals
    @funcaptcha_session_id = funcaptcha_session_id
    @funcaptcha_solved = funcaptcha_solved
    @funcaptcha_response = funcaptcha_response
    @funcaptcha_data_exchange = funcaptcha_data_exchange
    @country_code = country_code
    @explicit_marketing_consent = explicit_marketing_consent
  end

  sig { params(user: User, octocaptcha: Octocaptcha, visitor_id: T.nilable(Integer), spamurai_form_signals: T.nilable(SpamuraiFormSignals), funcaptcha_data_exchange: T.nilable(T::Hash[String, String]), country_code: T.nilable(String), explicit_marketing_consent: T.nilable(T::Boolean)).returns(String) }
  def self.create_and_send_verification_email(user:, octocaptcha:, visitor_id: nil, spamurai_form_signals: nil, funcaptcha_data_exchange: nil, country_code: nil, explicit_marketing_consent: false)
    password_hash = user.password ? GitHub::Password.create(user.password).to_s : nil
    verification = new(
      display_login: user.display_login, email: user.email,
      password_hash: password_hash,
      verification_token: UserEmail.generate_launch_code_verification,
      funcaptcha_session_id: octocaptcha.funcaptcha_session_id, funcaptcha_solved: octocaptcha.funcaptcha_solved, funcaptcha_response: octocaptcha.funcaptcha_response,
      visitor_id:, spamurai_form_signals:, funcaptcha_data_exchange:, country_code:, explicit_marketing_consent:
    )
    verification.save_and_send_verification_email
    T.must(verification.verification_id)
  end

  sig { params(persistent_client_id: String).returns(User) }
  def create_user(persistent_client_id)
    user = User.new(login: @display_login, password_hash: @password_hash)
    user.persistent_client_id = persistent_client_id
    user.time_zone_name = Time.zone.name
    user.add_email(email, primary: true, verified: true)

    GitHub.context.push(visitor_id: visitor_id)
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
    GitHub.context.push(funcaptcha_session_id: funcaptcha_session_id)
    GitHub.context.push(funcaptcha_solved: funcaptcha_solved)
    GitHub.context.push(funcaptcha_response: funcaptcha_response)

    user.save
    self.class.store.del(self.class.signup_data_key(T.must(verification_id)))
    user
  end

  sig { params(id: T.nilable(String)).returns(T::Boolean) }
  def self.exists?(id)
    find_email_verification(id).present?
  end

  sig { params(id: T.nilable(String)).returns(T.nilable(User::AccountlessEmailVerification)) }
  def self.find_email_verification(id)
    return unless id
    data = store.get(signup_data_key(id)).value!
    return unless data

    data = JSON.parse(data).merge(verification_id: id)

    spamurai_form_signals = data["spamurai_form_signals"].present? ? SpamuraiFormSignals.new(**data["spamurai_form_signals"].symbolize_keys) : nil
    data["spamurai_form_signals"] = spamurai_form_signals

    new(**data.symbolize_keys)
  end

  sig { void }
  def reset_verification_token_and_sent_email
    @verification_token = UserEmail.generate_launch_code_verification
    write_to_store
    send_verification_email
  end

  sig { returns(GitHub::KV) }
  def self.store
    SignupFlowKV.store
  end

  sig { params(id: String).returns(String) }
  def self.signup_data_key(id)
    "UserSignupData:#{id}"
  end

  sig { returns(User::AccountlessEmailVerification) }
  def save_and_send_verification_email
    @verification_id = SecureRandom.uuid
    write_to_store
    send_verification_email
    self
  end

  private

  sig { void }
  def send_verification_email
    SignupsMailer.accountless_code_verification(verification_id, email, verification_token).deliver_later
  end

  sig { void }
  def write_to_store
    self.class.store.set(
      self.class.signup_data_key(T.must(self.verification_id)),
      {
        display_login: display_login,
        email: email,
        password_hash: @password_hash,
        verification_token: verification_token,
        visitor_id: visitor_id,
        spamurai_form_signals: spamurai_form_signals,
        funcaptcha_session_id: funcaptcha_session_id,
        funcaptcha_solved: funcaptcha_solved,
        funcaptcha_response: funcaptcha_response,
        funcaptcha_data_exchange: funcaptcha_data_exchange,
        country_code: country_code,
        explicit_marketing_consent: explicit_marketing_consent
      }.to_json,
      expires: 2.hours.from_now,
    )
  end
end
