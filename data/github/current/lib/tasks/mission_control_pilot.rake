# typed: true
# frozen_string_literal: true

# Rake tasks for the Mission Control Agent CTA Pilot experiment.
# These tasks validate ExP's core capabilities before building the full Mission Control service.
#
# Usage:
#   bin/rake mission_control_pilot:validate            # Run full validation suite
#   bin/rake mission_control_pilot:check_assignment    # Validate assignment consistency
#   bin/rake mission_control_pilot:check_hydro         # Validate Hydro event emission
#   bin/rake mission_control_pilot:status              # Print experiment status summary
namespace :mission_control_pilot do
  task :protect do
    if %w[production staging].include?(Rails.env)
      fail "mission_control_pilot tasks are not intended to run in #{Rails.env}"
    end
  end

  desc "Run full Mission Control pilot validation suite"
  task validate: [:protect, :environment] do
    puts "=" * 72
    puts "Mission Control Agent CTA Pilot — ExP Validation"
    puts "=" * 72
    puts

    Rake::Task["mission_control_pilot:status"].invoke
    puts
    Rake::Task["mission_control_pilot:check_assignment"].invoke
    puts
    Rake::Task["mission_control_pilot:check_hydro"].invoke
    puts

    puts "=" * 72
    puts "Validation complete. Review results above for Go/No-Go decision."
    puts "=" * 72
  end

  desc "Print experiment configuration status"
  task status: [:protect, :environment] do
    puts "--- Experiment Configuration ---"
    puts "Namespace:      #{AzureEXP::Experiments::MissionControlPilot::NAMESPACE}"
    puts "Surface:        #{AzureEXP::Experiments::MissionControlPilot::SURFACE}"
    puts "Parameter:      #{AzureEXP::Experiments::MissionControlPilot::EXPERIMENT_PARAMETER}"
    puts "Feature Flag:   #{AzureEXP::Experiments::MissionControlPilot::FEATURE_FLAG}"
    puts

    # Verify experiment exists in config/experiments.json
    experiments_json = JSON.parse(File.read(Rails.root.join("config/experiments.json")))
    pilot = experiments_json["experiments"].find { |e| e["name"] == "mission_control_agent_cta_pilot" }

    if pilot
      puts "config/experiments.json:  FOUND"
      puts "  ID:          #{pilot['id']}"
      puts "  Surface:     #{pilot['surface']}"
      puts "  Namespace:   #{pilot['namespace']}"
      puts "  Variants:    #{pilot['variants'].map { |v| v['value'] }.join(', ')}"
    else
      puts "config/experiments.json:  NOT FOUND (add experiment entry)"
    end

    # Verify experiment exists in config/experiment_config.json
    config_json = JSON.parse(File.read(Rails.root.join("config/experiment_config.json")))
    ns = config_json["namespaces"].find { |n| n["name"] == "copilot_mission_control" }

    if ns
      puts "config/experiment_config.json:  FOUND (namespace: copilot_mission_control)"
      ns["experiments"].each do |exp|
        puts "  Experiment: #{exp['name']}"
        exp["variants"].each do |v|
          puts "    #{v['name']}: #{v['parameters']}"
        end
      end
    else
      puts "config/experiment_config.json:  NOT FOUND (add namespace)"
    end
  end

  desc "Validate ExP assignment consistency for test users"
  task check_assignment: [:protect, :environment] do
    puts "--- Assignment Validation ---"

    test_user_ids = ENV.fetch("USER_IDS", "").split(",").map(&:strip).map(&:to_i)

    if test_user_ids.empty?
      # Use a few sample users from the DB
      test_user_ids = User.where.not(type: "Organization").limit(5).pluck(:id)
      puts "No USER_IDS specified, using #{test_user_ids.size} sample users: #{test_user_ids.join(', ')}"
    end

    all_consistent = true
    treatment_count = 0
    control_count = 0

    test_user_ids.each do |uid|
      user = User.find_by(id: uid)
      unless user
        puts "  User #{uid}: NOT FOUND — skipping"
        next
      end

      result = AzureEXP::Experiments::MissionControlPilot.validate_consistency(user, calls: 10)

      variant_label = result[:assignments].first ? "treatment" : "control"
      consistency_label = result[:consistent] ? "CONSISTENT" : "INCONSISTENT"

      if result[:assignments].first
        treatment_count += 1
      else
        control_count += 1
      end

      all_consistent = false unless result[:consistent]

      puts "  User #{uid}: #{variant_label} — #{consistency_label} (#{result[:assignments].size} calls)"
    end

    total = treatment_count + control_count
    if total > 0
      puts
      puts "  Distribution: #{treatment_count}/#{total} treatment (#{(treatment_count.to_f / total * 100).round(1)}%), " \
           "#{control_count}/#{total} control (#{(control_count.to_f / total * 100).round(1)}%)"
      puts "  Consistency:  #{all_consistent ? 'ALL CONSISTENT' : 'INCONSISTENCIES DETECTED'}"
    else
      puts "  No users validated. Provide USER_IDS=1,2,3 or ensure sample users exist."
    end
  end

  desc "Validate Hydro event emission for ExP assignments"
  task check_hydro: [:protect, :environment] do
    puts "--- Hydro Event Emission Validation ---"
    puts
    puts "Hydro events are emitted automatically when ExP assignments are fetched."
    puts "The exp.responded event is published via GlobalInstrumenter and forwarded"
    puts "to Hydro with schema: hydro.schemas.github.exp.v0.TasApiResponse"
    puts
    puts "Required fields in each event:"
    puts "  - namespace (#{AzureEXP::Experiments::MissionControlPilot::NAMESPACE})"
    puts "  - assignment_surface (#{AzureEXP::Experiments::MissionControlPilot::SURFACE})"
    puts "  - current_experiments (JSON of variant assignments)"
    puts "  - assignment_context (ExP context string)"
    puts "  - randomization_unit (ACTOR for user-based)"
    puts "  - randomization_id (user ID)"
    puts
    puts "To spot-check events, query Hydro for:"
    puts "  schema = 'hydro.schemas.github.exp.v0.TasApiResponse'"
    puts "  AND namespace = '#{AzureEXP::Experiments::MissionControlPilot::NAMESPACE}'"
    puts
    puts "Verify that the check_assignment task above triggered assignment fetches."
    puts "Each assignment fetch emits exactly one Hydro event (see test suite for validation)."
  end
end
