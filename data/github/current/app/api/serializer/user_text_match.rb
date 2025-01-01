# typed: true
# frozen_string_literal: true

module Api::Serializer
  class UserTextMatch
    include TextMatch

    def self.supported_field_names
      %w(login login.ngram email email.plain name).freeze
    end

    def object_type
      "User"
    end

    def object_url_suffix
      "/users/#{user.login_for_api}"
    end

    def property
      case field_name
      when "login", "login.ngram" then "login"
      when "email", "email.plain" then "email"
      when "name"                 then "name"
      end
    end

    private

    def user
      search_result["_model"]
    end
  end
end
