# typed: true
# frozen_string_literal: true

class CodespacesOrgDowngradedMailer < ApplicationMailer
  self.mailer_name = "mailers/codespaces_org_downgraded"

  layout "layouts/primer_layout"

  def downgraded(admin, org, codespace_count, deletion_date)
    # navigate to http://github.localhost/rails/mailers/codespaces_org_downgraded/downgraded?part=text%2Fhtml
    # to preview this mailer
    @admin = admin
    @org = org
    @codespace_count = codespace_count
    @deletion_date = deletion_date

    premail(
      from: github_noreply,
      to: user_email(admin),
      subject: "Your organization's codespaces will be deleted as a result of your recent downgrade",
    )
  end
end
