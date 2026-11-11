# frozen_string_literal: true

# Create test alert data for local testing of alert events in PRs.
#
# Usage:
#   bin/rails runner script/seeds/osslicensecompliance/alert_seeds.rb

require_relative "seed_helper"

abort "This script is intended to be run in a Codespace in development." unless running_on_localhost?
seed_context = setup_context
abort "Failed to set up context. Ensure the 2 required pull requests and users exist in http://github.localhost/github/public-server" if seed_context.nil?

BaseAlert = Struct.new(
  :alert_id,
  :alert_number,
  :repository_id,
  :organization_id,
  :enterprise_id,
  :pull_request_number,
  :pull_request_id,
  :manifest_name,
  :package_manager,
  :package_name,
  :package_version,
  :spdx_license_expression,
  :status,
  :closure_reason,
  keyword_init: true
)

StatusChangeMessage = Struct.new(:value, keyword_init: true)

# Create test alert data (array of hashes)
def seed_initial_open_alerts(seed_context)
  repo = seed_context.repo
  pull_request = seed_context.pull_request

  puts "Defining alerts to be added to PR ##{pull_request.number} (id=#{pull_request.id}) in repo id=#{repo.id}"
  open_license_alerts = [
    seed_alert1_open(seed_context),
    seed_alert2_open(seed_context),
    seed_alert3_open(seed_context),
    seed_alert4_open(seed_context),
    seed_alert6_open(seed_context),
    seed_alert7_open(seed_context),
  ]

  # Call the PrCommentsManager (without remediation guidance)
  puts "\nCalling manage_automated_review_comments to add the alerts in PR http://github.localhost/github/public-server/pull/1"
  LicenseCompliance::PrCommentsManager.manage_automated_review_comments(
    pull_request: pull_request,
    open_license_alerts: open_license_alerts
  )

  sideeffect_pull_request = seed_context.pull_request_for_sideeffect
  open_license_alerts = [
    seed_alert5_open(seed_context),
  ]
  puts "\nCalling manage_automated_review_comments to add an alert in another PR http://github.localhost/github/public-server/pull/2"
  LicenseCompliance::PrCommentsManager.manage_automated_review_comments(
    pull_request: sideeffect_pull_request,
    open_license_alerts: open_license_alerts
  )
end

def seed_status_changes(seed_context)
  repo = seed_context.repo
  pull_request = seed_context.pull_request

  puts "\nUpdating status for alerts in PR ##{pull_request.number} (id=#{pull_request.id}) in repo id=#{repo.id}"
  processor = GitHub::StreamProcessors::LicenseComplianceAlertStatusChangedProcessor.new
  processor.process_message(seed_alert2_status_change_to_review_requested(seed_context))
  processor.process_message(seed_alert3_status_change_to_review_requested(seed_context))
  processor.process_message(seed_alert3_status_change_to_closed_with_licenses_added(seed_context))
  processor.process_message(seed_alert5_status_change_to_review_requested(seed_context)) # Need to process this alert before #4 which will close it by side-effect
  processor.process_message(seed_alert5_status_change_to_closed_by_side_effect(seed_context))
  processor.process_message(seed_alert4_status_change_to_review_requested(seed_context))
  processor.process_message(seed_alert4_status_change_to_closed_with_package_exception(seed_context))
  processor.process_message(seed_alert6_status_change_to_review_requested(seed_context))
  processor.process_message(seed_alert6_status_change_to_open_by_expiration(seed_context))
  processor.process_message(seed_alert7_status_change_to_review_requested(seed_context))
  processor.process_message(seed_alert7_status_change_to_denied(seed_context))
  processor.process_message(seed_alert7_status_change_to_review_requested_after_denial(seed_context))
  processor.process_message(seed_alert7_status_change_to_closed_with_licenses_added(seed_context))
end

def initialize_base_alert(alert_num, seed_context, manifest_name, package_manager, package_name, package_version, spdx_license_expression)
  repo = seed_context.repo
  pull_request = seed_context.pull_request

  BaseAlert.new(
    alert_id: alert_num,
    alert_number: alert_num,
    repository_id: repo.id,
    organization_id: repo.owner_id,
    enterprise_id: repo.business_id && Google::Protobuf::Int64Value.new(value: repo.business_id),
    pull_request_number: pull_request.number,
    pull_request_id: pull_request.id,
    manifest_name: manifest_name,
    package_manager: package_manager,
    package_name: package_name,
    package_version: package_version,
    spdx_license_expression: spdx_license_expression,
    status: :ALERT_STATUS_OPEN,
    closure_reason: nil,
  )
end

def initialize_hydro_alert(alert)
  Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert.new(
    alert_id: alert.alert_id,
    alert_number: alert.alert_number,
    repository_id: alert.repository_id,
    organization_id: alert.organization_id,
    enterprise_id: alert.enterprise_id,
    pull_request_number: alert.pull_request_number,
    pull_request_id: alert.pull_request_id,
    manifest_name: alert.manifest_name,
    package_manager: alert.package_manager,
    package_name: alert.package_name,
    package_version: alert.package_version,
    spdx_license_expression: alert.spdx_license_expression,
    status: alert.status,
    closure_reason: alert.closure_reason,
  )
end

def initialize_status_change_message(alert, new_status:, closure_reason:, previous_status:, user_id:, closure_user_id:, comment:)
  StatusChangeMessage.new(
    value: {
      alert: {
        alert_id: alert.alert_id,
        alert_number: alert.alert_number,
        repository_id: alert.repository_id,
        organization_id: alert.organization_id,
        enterprise_id: alert.enterprise_id,
        pull_request_number: alert.pull_request_number,
        pull_request_id: alert.pull_request_id,
        manifest_name: alert.manifest_name,
        package_manager: alert.package_manager,
        package_name: alert.package_name,
        package_version: alert.package_version,
        spdx_license_expression: alert.spdx_license_expression,
        status: new_status,
        closure_reason: closure_reason,
      },
      previous_status: previous_status,
      user_id: user_id,
      comment: { value: comment },
      closure_user_id: closure_user_id
    }
  )
end

def seed_alert1_base_alert(seed_context)
  initialize_base_alert(
    1,
    seed_context,
    "package.json",
    :PACKAGE_MANAGER_NPM,
    "express",
    "4.18.0",
    "GPL-2.0"
  )
end

def seed_alert1_open(seed_context)
  puts "Alert 1: Creating open alert with no events..."
  base_alert = seed_alert1_base_alert(seed_context)
  alert_message = initialize_hydro_alert(base_alert)
  print_alert_created(base_alert)
  alert_message
end

def seed_alert2_base_alert(seed_context)
  initialize_base_alert(
    2,
    seed_context,
    "Gemfile.lock",
    :PACKAGE_MANAGER_RUBYGEMS,
    "rails",
    "7.0.0",
    "AGPL-3.0"
  )
end

def seed_alert2_open(seed_context)
  puts "Alert 2: Creating initial open alert..."
  base_alert = seed_alert2_base_alert(seed_context)
  alert_message = initialize_hydro_alert(base_alert)
  print_alert_created(base_alert)
  alert_message
end

def seed_alert2_status_change_to_review_requested(seed_context)
  puts "Alert 2: Updating status to review requested..."
  base_alert = seed_alert2_base_alert(seed_context)
  new_status = :ALERT_STATUS_REVIEW_REQUESTED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_OPEN,
    user_id: seed_context.requester.id,
    closure_user_id: nil,
    closure_reason: :CLOSURE_REASON_INACCURATE_LICENSE,
    comment: "Test comment for review request",
  )
  print_alert_status_change(base_alert, new_status, "review requested")
  change_message
end

def seed_alert3_base_alert(seed_context)
  initialize_base_alert(
    3,
    seed_context,
    "requirements.txt",
    :PACKAGE_MANAGER_PIP,
    "django",
    "4.2.0",
    "BSD-3-Clause"
  )
end

def seed_alert3_open(seed_context)
  puts "Alert 3: Creating initial open alert..."
  base_alert = seed_alert3_base_alert(seed_context)
  alert_message = initialize_hydro_alert(base_alert)
  print_alert_created(base_alert)
  alert_message
end

def seed_alert3_status_change_to_review_requested(seed_context)
  puts "Alert 3: Updating status to review requested..."
  base_alert = seed_alert3_base_alert(seed_context)
  new_status = :ALERT_STATUS_REVIEW_REQUESTED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_OPEN,
    user_id: seed_context.requester.id,
    closure_user_id: nil,
    closure_reason: nil,
    comment: "Test comment for review request",
  )
  print_alert_status_change(base_alert, new_status, "review requested")
  change_message
end

def seed_alert3_status_change_to_closed_with_licenses_added(seed_context)
  puts "Alert 3: Updating status to closed with licenses added..."
  base_alert = seed_alert3_base_alert(seed_context)
  new_status = :ALERT_STATUS_CLOSED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_REVIEW_REQUESTED,
    user_id: seed_context.reviewer.id,
    closure_user_id: seed_context.requester.id,
    closure_reason: :CLOSURE_REASON_INACCURATE_LICENSE,
    comment: "Test comment for closed with licenses added",
  )
  print_alert_status_change(base_alert, new_status, "closed with licenses added")
  change_message
end

def seed_alert4_base_alert(seed_context)
  initialize_base_alert(
    4,
    seed_context,
    "go.mod",
    :PACKAGE_MANAGER_GOMOD,
    "github.com/example/internal",
    "v1.2.3",
    "AGPL-3.0"
  )
end

def seed_alert4_open(seed_context)
  puts "Alert 4: Creating initial open alert..."
  base_alert = seed_alert4_base_alert(seed_context)
  alert_message = initialize_hydro_alert(base_alert)
  print_alert_created(base_alert)
  alert_message
end

def seed_alert4_status_change_to_review_requested(seed_context)
  puts "Alert 4: Updating status to review requested..."
  base_alert = seed_alert4_base_alert(seed_context)
  new_status = :ALERT_STATUS_REVIEW_REQUESTED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_OPEN,
    user_id: seed_context.requester.id,
    closure_user_id: nil,
    closure_reason: nil,
    comment: "Test comment for review request",
  )
  print_alert_status_change(base_alert, new_status, "review requested")
  change_message
end

def seed_alert4_status_change_to_closed_with_package_exception(seed_context)
  puts "Alert 4: Updating status to closed with package exception..."
  base_alert = seed_alert4_base_alert(seed_context)
  new_status = :ALERT_STATUS_CLOSED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_REVIEW_REQUESTED,
    user_id: seed_context.reviewer.id,
    closure_user_id: seed_context.requester.id,
    closure_reason: :CLOSURE_REASON_INACCURATE_LICENSE,
    comment: "Test comment for closed with package exception",
  )
  print_alert_status_change(base_alert, new_status, "closed with package exception")
  change_message
end

def seed_alert5_base_alert(seed_context)
  base_alert = initialize_base_alert(
    5,
    seed_context,
    "go.mod",
    :PACKAGE_MANAGER_GOMOD,
    "github.com/example/internal",
    "v1.2.3",
    "AGPL-3.0"
  )
  base_alert.pull_request_id = seed_context.pull_request_for_sideeffect.id
  base_alert
end

def seed_alert5_open(seed_context)
  puts "Alert 5: Creating initial open alert..."
  base_alert = seed_alert5_base_alert(seed_context)
  alert_message = initialize_hydro_alert(base_alert)
  print_alert_created(base_alert)
  alert_message
end

def seed_alert5_status_change_to_review_requested(seed_context)
  puts "Alert 5: Updating status to review requested..."
  base_alert = seed_alert5_base_alert(seed_context)
  new_status = :ALERT_STATUS_REVIEW_REQUESTED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_OPEN,
    user_id: seed_context.requester.id,
    closure_user_id: nil,
    closure_reason: nil,
    comment: "Test comment for review request",
  )
  print_alert_status_change(base_alert, new_status, "review requested in another PR")
  change_message
end

def seed_alert5_status_change_to_closed_by_side_effect(seed_context)
  puts "Alert 5: Updating status to closed by side effect..."
  base_alert = seed_alert5_base_alert(seed_context)
  new_status = :ALERT_STATUS_CLOSED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_REVIEW_REQUESTED,
    user_id: nil,
    closure_user_id: nil,
    closure_reason: nil,
    comment: "Test comment for closed by side effect",
  )
  print_alert_status_change(base_alert, new_status, "closed by side effect")
  change_message
end

def seed_alert6_base_alert(seed_context)
  initialize_base_alert(
    6,
    seed_context,
    "package.json",
    :PACKAGE_MANAGER_NPM,
    "moment",
    "2.29.1",
    "LGPL-2.1"
  )
end

def seed_alert6_open(seed_context)
  puts "Alert 6: Creating initial open alert..."
  base_alert = seed_alert6_base_alert(seed_context)
  alert_message = initialize_hydro_alert(base_alert)
  print_alert_created(base_alert)
  alert_message
end

def seed_alert6_status_change_to_review_requested(seed_context)
  puts "Alert 6: Updating status to review requested..."
  base_alert = seed_alert6_base_alert(seed_context)
  new_status = :ALERT_STATUS_REVIEW_REQUESTED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_OPEN,
    user_id: seed_context.requester.id,
    closure_user_id: nil,
    closure_reason: nil,
    comment: "Test comment for review request",
  )
  print_alert_status_change(base_alert, new_status, "review requested")
  change_message
end

def seed_alert6_status_change_to_open_by_expiration(seed_context)
  puts "Alert 6: Updating status to open by expiration..."
  base_alert = seed_alert6_base_alert(seed_context)
  new_status = :ALERT_STATUS_OPEN
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_REVIEW_REQUESTED,
    user_id: nil,
    closure_user_id: nil,
    closure_reason: nil,
    comment: "",
  )
  print_alert_status_change(base_alert, new_status, "open by expiration")
  change_message
end

def seed_alert7_base_alert(seed_context)
  initialize_base_alert(
    7,
    seed_context,
    "package.json",
    :PACKAGE_MANAGER_NPM,
    "lodash",
    "4.17.20",
    "GPL-3.0"
  )
end

def seed_alert7_open(seed_context)
  puts "Alert 7: Creating initial open alert..."
  base_alert = seed_alert7_base_alert(seed_context)
  alert_message = initialize_hydro_alert(base_alert)
  print_alert_created(base_alert)
  alert_message
end

def seed_alert7_status_change_to_review_requested(seed_context)
  puts "Alert 7: Updating status to review requested..."
  base_alert = seed_alert7_base_alert(seed_context)
  new_status = :ALERT_STATUS_REVIEW_REQUESTED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_OPEN,
    user_id: seed_context.requester.id,
    closure_user_id: nil,
    closure_reason: :CLOSURE_REASON_PRIVATE_PACKAGE,
    comment: "Test comment for review request",
  )
  print_alert_status_change(base_alert, new_status, "review requested")
  change_message
end

def seed_alert7_status_change_to_denied(seed_context)
  puts "Alert 7: Updating status to denied..."
  base_alert = seed_alert7_base_alert(seed_context)
  new_status = :ALERT_STATUS_REVIEW_DENIED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_REVIEW_REQUESTED,
    user_id: seed_context.reviewer.id,
    closure_user_id: nil,
    closure_reason: :CLOSURE_REASON_PRIVATE_PACKAGE,
    comment: "Test comment for denied status",
  )
  print_alert_status_change(base_alert, new_status, "denied")
  change_message
end

def seed_alert7_status_change_to_review_requested_after_denial(seed_context)
  puts "Alert 7: Updating status to review requested..."
  base_alert = seed_alert7_base_alert(seed_context)
  new_status = :ALERT_STATUS_REVIEW_REQUESTED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_REVIEW_DENIED,
    user_id: seed_context.requester.id,
    closure_user_id: nil,
    closure_reason: :CLOSURE_REASON_PRIVATE_PACKAGE,
    comment: "Test comment for review request after denial",
  )
  print_alert_status_change(base_alert, new_status, "review requested after denial")
  change_message
end

def seed_alert7_status_change_to_closed_with_licenses_added(seed_context)
  puts "Alert 7: Updating status to closed with licenses added..."
  base_alert = seed_alert7_base_alert(seed_context)
  new_status = :ALERT_STATUS_CLOSED
  change_message = initialize_status_change_message(
    base_alert,
    new_status: new_status,
    previous_status: :ALERT_STATUS_REVIEW_REQUESTED,
    user_id: seed_context.reviewer.id,
    closure_user_id: seed_context.requester.id,
    closure_reason: :CLOSURE_REASON_PRIVATE_PACKAGE,
    comment: "Test comment for closed with licenses added",
  )
  print_alert_status_change(base_alert, new_status, "closed with licenses added")
  change_message
end

def print_alert_created(alert)
  puts("✓ Opened Alert #{alert.alert_number}: #{alert.package_name}@#{alert.package_version}")
  puts
end

def print_alert_status_change(alert, new_status, workflow)
  puts("✓ Status Changed to #{new_status} for Alert #{alert.alert_number}: #{alert.package_name}@#{alert.package_version} (#{workflow})")
  puts
end

seed_initial_open_alerts(seed_context)
seed_status_changes(seed_context)

puts "\n-------------------------------------------------------------------------------------"
puts
puts "Post Generation Steps:"
puts
puts "  If you haven't already done so, run the seeds in OLC using:"
puts
puts "    make gh-codespace-seed"
puts
puts "  This creates alerts and event data in the OLC database which drives the Alert show pages."
puts "  This also allows you to click the View alert details link in the PR to navigate to the"
puts "  Alert show page."
puts
puts "Want to start over with a fresh set of alerts?"
puts
puts "  - clear seeds: 'bin/rails runner script/seeds/osslicensecompliance/alert_reset.rb'"
puts "  - run seeds:   'bin/rails runner script/seeds/osslicensecompliance/alert_seeds.rb'"
puts
puts "-------------------------------------------------------------------------------------"
