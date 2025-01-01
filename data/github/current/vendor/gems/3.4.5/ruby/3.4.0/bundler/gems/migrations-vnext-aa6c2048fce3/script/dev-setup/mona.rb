  mona = User.find_by(login: "monalisa_avo")

  if OauthAccess.exists?(user_id: mona.id)
    puts "monalisa_avo seems to already have a PAT, skipping"
    exit 0
  end

  token_suffix = "MonalisaTheOctoAvoMonalisaTheOctoAvo"
  predetermined_token = "ghp_#{token_suffix}"
  hashed_token = OauthAccess.hash_token(predetermined_token)
  unless OauthAccess.find_by(user_id: mona.id, hashed_token: hashed_token).present?
    scopes = Api::AccessControl.scopes.select { |_name, scope| scope.grantable? && scope.parent.nil? }.keys
    scopes = scopes.reject { |scope| scope == "site_admin" } if GitHub.enterprise? # this is inelegant, not sure if there's a better way to exclude scopes that are not compatible with enterprise
    access = mona.oauth_accesses.create! do |acc|
      acc.application_id = ::OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
      acc.application_type = ::OauthApplication::PERSONAL_TOKENS_APPLICATION_TYPE
      acc.description = "Fixed db/seed.rb PAT <PAT_PREFIX>_#{token_suffix}"
      acc.scopes = OauthAccess.normalize_scopes(scopes, visibility: :all)
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      OauthAccess.connection.update(Arel.sql(<<-SQL, id: access.id, hashed_token: OauthAccess.hash_token(predetermined_token), token_last_eight: predetermined_token.last(8), expires_at_timestamp: 1.year.from_now.to_i))
      UPDATE oauth_accesses
        SET
          hashed_token = :hashed_token,
          token_last_eight = :token_last_eight,
          updated_at = now(),
          expires_at_timestamp = :expires_at_timestamp
          WHERE
          id = :id
      SQL
    end
  end
