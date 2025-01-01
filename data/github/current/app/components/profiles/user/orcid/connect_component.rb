# typed: strict
# frozen_string_literal: true

module Profiles
  module User
    module Orcid
      class ConnectComponent < ApplicationComponent
        extend T::Sig

        include SvgHelper
      end
    end
  end
end
