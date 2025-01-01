# typed: true
# frozen_string_literal: true

class AssetStatusMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/asset_status"

  def approaching_quota(asset_status)
    @asset_status = asset_status
    @user = asset_status.owner

    recipients = user_or_billing_recipients(@user)

    mail(recipients.merge(
      from: github,
      subject: "[GitHub] At 80% of Git LFS data quota for #{@user}",
    ))
  end

  def over_quota(asset_status)
    @asset_status = asset_status
    @user = asset_status.owner

    recipients = user_or_billing_recipients(@user)

    mail(recipients.merge(
      from: github,
      subject: "[GitHub] At 100% of Git LFS data quota for #{@user}",
    ))
  end

  def over_quota_disable(asset_status)
    @asset_status = asset_status
    @user = asset_status.owner

    if @asset_status.notified_state != "disabled_over_quota"
      GitHub.logger.error(
        :exception => RuntimeError.new("Invalid Asset::Status state when sending over_quota_disable email: #{Asset::Status.notified_states[@asset_status.notified_state]}"),
        :app => "github-user",
        "gh.user.id" => @user.id,
        "gh.asset_status.id" => @asset_status.id,
      )
    end

    recipients = user_or_billing_recipients(@user)

    mail(recipients.merge(
      from: github,
      subject: "[GitHub] Git LFS disabled for #{@user}",
    ))
  end
end
