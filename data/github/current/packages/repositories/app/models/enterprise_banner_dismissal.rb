# typed: strict
# frozen_string_literal: true

class EnterpriseBannerDismissal < ApplicationRecord::Collab
  belongs_to :enterprise_banner
  include ::Users::BelongsToUser
  belongs_to_user_via_domain
end
