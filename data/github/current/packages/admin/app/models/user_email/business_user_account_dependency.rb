# typed: true
# frozen_string_literal: true

module UserEmail::BusinessUserAccountDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { UserEmail }

  included do
    T.bind(self, T.class_of(UserEmail))
    after_commit :update_business_user_accounts
  end

  private

  def update_business_user_accounts
    return unless verified?
    BusinessUserAccount.where(user_id: user_id).where.not(business_id: nil).includes(:business).each do |bua|
      BusinessUserAccountUpdateUserJob.perform_later(bua.business, user_account_ids: [bua.id]) if bua.business.present?
    end
  end
end
