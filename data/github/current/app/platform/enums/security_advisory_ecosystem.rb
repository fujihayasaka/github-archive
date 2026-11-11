# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SecurityAdvisoryEcosystem < Platform::Enums::Base
      visibility :public

      description "The possible ecosystems of a security vulnerability's package."

      ::AdvisoryDB::Ecosystems.public.each do |ecosystem|
        value ecosystem.name.upcase, ecosystem.description, value: ecosystem.name.downcase
      end
    end
  end
end
