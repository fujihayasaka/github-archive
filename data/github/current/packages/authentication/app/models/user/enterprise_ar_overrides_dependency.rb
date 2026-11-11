# typed: true
# frozen_string_literal: true

module User::EnterpriseArOverridesDependency
  extend T::Helpers
  requires_ancestor { User }

  if GitHub.enterprise?
    DENIED_ATTRIBUTES = [:bcrypt_auth_token, :auth_token, :session_fingerprint, :token_secret, :password_hash]

    # Public: Overrides inspect to only return allowed keys for a User.
    # For use in enterprise environment to prevent sensitive attributes
    # from showing up in stack traces.
    def inspect
      cols = User.column_names.reject do |name|
        DENIED_ATTRIBUTES.include?(name.to_sym)
      end

      attributes_as_nice_string = cols.collect do |name|
        if has_attribute?(name) || new_record?
          "#{name}: #{attribute_for_inspect(name)}"
        end
      end.compact.join(", ")

      "#<#{self.class} #{attributes_as_nice_string}>"
    end
  end
end
