# typed: true
# frozen_string_literal: true

class Stafftools::ResearchParticipantsController < StafftoolsController
  before_action :dotcom_required

  def index
    render "stafftools/research_participants/index"
  end

  def create
    control_org_name = params[:control_org]
    control_org = Organization.find_by_login(control_org_name)
    return redirect_to stafftools_research_participants_path, flash: { error: "Control org '#{control_org_name}' does not exist" } if control_org.nil?

    treatment_org_name = params[:treatment_org]
    treatment_org = Organization.find_by_login(treatment_org_name)
    return redirect_to stafftools_research_participants_path, flash: { error: "Treatment org '#{treatment_org_name}' does not exist" } if treatment_org.nil?

    emails = params[:emails].split("\n")
    emails.each do |email|
      result = provision(prefix: params[:username_prefix], email: email.strip.downcase, control_org:, treatment_org:)
      if result.failed?
        msg = "Provisioning #{email} failed: #{result.error_message}"
        return redirect_to stafftools_research_participants_path, flash: { error: msg }
      end
    end

    redirect_to stafftools_research_participants_path, notice: "Users provisioned!"
  end

  def export # rubocop:todo GitHub/UseRestfulActions
    org_name = params[:org]
    org = Organization.find_by_login(org_name)
    return redirect_to stafftools_research_participants_path, flash: { error: "Org '#{org_name}' does not exist" } if org.nil?

    ids = org.member_ids(action: :read)
    members = User.where(id: ids).includes(:emails)
    csv = "Organization,Username,Email\n"
    members.each do |member|
      csv += "#{org_name},#{member.login},#{member.emails[1].email}\n"
    end
    send_data(csv, type: "text/csv", filename: "participants.csv")
  end

  private

  memoize def email_domain
    host_name_without_port = GitHub.host_name.gsub(/:\d+\z/, "")
    "research.noreply.#{host_name_without_port}"
  end

  def provision(prefix:, email:, control_org:, treatment_org:)
    suffix = Digest::SHA256.hexdigest("#{prefix}#{email}")[0, 8]
    login = "#{prefix}#{suffix}"

    if existing_user = User.find_by_login(login)
      return Result.failed("User for #{email} already exists: #{existing_user.login}")
    end

    user = User.new_with_random_password(login)
    user.time_zone_name = Time.zone.name
    user.require_email_verification = false
    # We need to generate a unique email for them since we can't have duplicate emails
    user.add_email("#{login}@#{email_domain}", verified: true, is_primary: true)
    if user.save
      user.add_email(email, verified: true)

      reset = PasswordReset.new(
        user:,
        email:,
        force: true,
        expires: 7.days.from_now,
      )
      if reset.valid?
        ResearchParticipantsMailer.invite_user(user, email, reset.link, reset.expires.to_s).deliver_later
      else
        return Result.failed("Password reset failed: #{reset.error_message}")
      end
    else
      return Result.failed("Creating user #{login} failed: #{user.errors.full_messages.join(", ")}")
    end

    org = rand > 0.5 ? control_org : treatment_org
    org.add_member(user)

    Result.success
  end

  class Result
    attr_reader :error_message

    def self.success(); new(:success) end

    def self.failed(error_message)
      new(:failed, error_message:)
    end

    def initialize(status, error_message: nil)
      @status = status
      @error_message = error_message
    end

    def success?
      @status == :success
    end

    def failed?
      @status == :failed
    end
  end
end
