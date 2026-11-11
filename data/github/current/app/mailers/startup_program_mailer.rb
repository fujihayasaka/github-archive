# typed: true
# frozen_string_literal: true

class StartupProgramMailer < ApplicationMailer
  include GitHub::Memoizer
  self.mailer_name = "mailers/startup_program"

  layout "layouts/primer_layout_minimal"

  sig { params(entity: T.any(Business, Organization)).void }
  def coupon_expiration(entity)
    coupon_redemption = entity.coupon_redemption
    return unless coupon_redemption

    @first_year = year_one_coupons.include?(coupon_redemption.coupon)
    @days_to_expire = (coupon_redemption.expires_at.in_time_zone.to_date - GitHub::Billing.today).to_i
    subject_suffix = @first_year ? "#{@days_to_expire} Day Coupon Expiration Reminder" : "Program Graduation Discount"

    stats_tag = "#{@first_year ? 'year_1' : 'year_2'}_expire_#{@days_to_expire}"
    GitHub.dogstats.increment("mailer.startups_program_coupon_expiration_email.count", tags: [stats_tag])
    GitHub.logger.info("Sending startups coupon expiration email", {
      "code.function" => __method__,
      "code.namespace" => self.class.name,
      "business.id" => entity.id,
      "template.name" => "coupon_expiration"
    })

    premail(
      from: github_startups_renewal,
      bcc: coupon_redemption_recipients(entity),
      subject: "[GitHub for Startups] - #{subject_suffix}",
      template_name: "coupon_expiration",
    )
  end

  private

  def coupon_redemption_recipients(entity)
    case entity
    when Business
      entity.owners.map { |u| user_email(u) }.compact.uniq
    when Organization
      entity.billing_email
    end
  end

  def github_startups_renewal
    %{"GitHub" <#{GitHub.startup_renewals_email}>}
  end

  memoize def year_one_coupons
    Coupon
      .where(code: %w[GFSYR1 GFSPartnerYR1])
      .or(Coupon.where("code LIKE ?", "gfs-%"))
      .or(Coupon.where("code LIKE ?", "gfspartner-%"))
  end
end
