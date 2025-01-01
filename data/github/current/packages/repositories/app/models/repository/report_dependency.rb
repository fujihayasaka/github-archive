# typed: false
# frozen_string_literal: true

module Repository::ReportDependency

  def can_report?(viewer)
    return false unless GitHub.can_report?
    return false if owner&.display_login == viewer&.display_login

    public? && visible? && !access.disabled?
  end

end
