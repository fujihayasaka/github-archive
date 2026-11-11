# typed: strict
# frozen_string_literal: true

class EnterpriseBannerDismissal < ApplicationRecord::Collab
  belongs_to :enterprise_banner
  belongs_to :user
end
