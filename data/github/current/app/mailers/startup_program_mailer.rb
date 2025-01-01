# typed: true
# frozen_string_literal: true

class StartupProgramMailer < ApplicationMailer
  include GitHub::Memoizer
  self.mailer_name = "mailers/startup_program"

  layout "layouts/primer_layout_minimal"

  def welcome(business)
    @business = business
    return if @business.owners.count.zero?

    GitHub.dogstats.increment("mailer.startups_program_welcome.count")
    GitHub.logger.info("Sending startups program welcome email", {
      "code.function" => __method__,
      "code.namespace" => self.class.name,
      "business.id" => business.id,
      "business_startups_program.status" => business.startups_program&.status,
      "template.name" => "welcome_email"
    })

    premail(
      from: github_startups,
      bcc: business_owner_emails,
      subject: "Welcome to GitHub for Startups",
    )
  end

  def expiration_renewal(business)
    return unless business.part_of_startup_program?
    return if business.startups_program.graduated?
    @business = business

    return if invoice_end_date > 30.days.from_now

    @first_year = business.startups_program.year_1?
    @expiration_date = invoice_end_date.strftime("%Y-%m-%d")
    @days_to_expire = (invoice_end_date.to_date - GitHub::Billing.today).to_i

    stats_tag = "#{@first_year ? 'year_1' : 'year_2'}_expiration_renewal_#{@days_to_expire}"
    GitHub.dogstats.increment("mailer.startups_program_renewal_email.count", tags: [stats_tag])
    GitHub.logger.info("Sending startups program welcome email", {
      "code.function" => __method__,
      "code.namespace" => self.class.name,
      "business.id" => business.id,
      "template.name" => "expiration_renewal"
    })

    premail(
      from: github_startups_renewal,
      bcc: program_expiration_recipients,
      subject: "[GitHub for Startups] - Year #{@first_year ? "1" : "2"} Program Graduation",
      template_name: "expiration_renewal",
    )
  end

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

  def business_owner_emails
    @business.owners.map { |u| user_email(u) }.compact.uniq
  end

  def program_expiration_recipients
    owners_emails = business_owner_emails

    return owners_emails unless owners_emails.empty?

    @business.billing_email
  end

  def coupon_redemption_recipients(entity)
    case entity
    when Business
      entity.owners.map { |u| user_email(u) }.compact.uniq
    when Organization
      entity.billing_email
    end
  end

  def github_startups
    %{"GitHub" <#{GitHub.startups_email}>}
  end

  def github_startups_renewal
    %{"GitHub" <#{GitHub.startup_renewals_email}>}
  end

  def invoice_end_date
    @business.customer.billing_end_date
  end

  def expire_in_three_days?
    @expire_in == 3
  end

  def expire_in_thirty_days?
    @expire_in = 30
  end

  memoize def startups_program
    @business.startups_program
  end

  memoize def year_one_coupons
    Coupon
      .where(code: %w[GFSYR1 GFSPartnerYR1])
      .or(Coupon.where("code LIKE ?", "gfs-%"))
      .or(Coupon.where("code LIKE ?", "gfspartner-%"))
  end

  memoize def year_two_coupons
    Coupon.where(code: %w[GFSYR2 GFSPartnerYR2 MSYR2])
  end
end
