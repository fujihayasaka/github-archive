# typed: true
# frozen_string_literal: true

require "#{GitHub::AppEnvironment.root}/config/environment"
require "optparse"

# To run this transition using the new #dotcom-transition-ops channel:
# 1. Submit a PR for review by the transitions group (can just be a new comment)
# 2. Once approved, run the transition using the chatops command:
#   .transitions run <pull-request-url> <environment-or-*> <file-name-of-transition> <arguments>
#   example: .transitions run https://github.com/github/gitcoin/pull/1234 production bulk_coupon_generator.rb -d
#   -c 500 -p "ISV-Success-Program-12months" -e "1 year" -x '2024-01-06' -g microsoft -u 420.0
# For more details, see: https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/

# DEPRECATED:
# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/bulk_coupon_generator.rb | tee -a /tmp/bulk_coupon_generator.log
#   gudo bin/safe-ruby lib/github/transitions/bulk_coupon_generator.rb -c YOUR_COUNT -p YOUR_PREFIX -n YOUR_NOTE
#   arguments: [quantity] [prefix] '[note]'
#   running without quantity does nothing

BATCH_LIMIT = 1000 # don't let this script go hog wild

module GitHub
  module Transitions
    class BulkCouponGenerator < LegacyTransition
      # Generate bulk coupons
      #
      # Returns nothing.

      def perform(count:, prefix: "gh-bulk", note: "bulk coupon", expires_at: nil,
                  dry_run: false, duration: "6 months", group: "si-bulk", discount: 1, plan: nil)
        count = count.to_i
        # prevent generating unpredictable quantities of coupon from weird input

        raise ArgumentError, "count should be greater than 0" unless count > 0
        #to_i deals with non-integer input

        # prevent generating enormous volumes of coupon through typos and such

        raise ArgumentError, \
        "That's a lot of coupons, buckeroo. Let's keep it under #{BATCH_LIMIT} per batch" \
        unless count <= BATCH_LIMIT

        # Convert expires_at to DateTime if provided
        expires_at = DateTime.parse(expires_at) if expires_at

        log "Starting transition #{self.class.to_s.underscore}"

        total = 0

        until total == count
          create_coupon \
            discount: discount,
            dry_run: dry_run,
            duration: duration,
            expires_at: expires_at,
            group: group,
            note: note,
            plan: plan,
            prefix: prefix
          total += 1
        end

        log ""
        log "Generated #{total} coupons"
      end

      def create_coupon(prefix:, note:, dry_run:, duration:, group:, discount:, plan: nil, expires_at: nil)
        non_sequential_token = SecureRandom.hex(4)[0, 7] #Prevent guessing more coupons

        coupon_name = "#{prefix}-#{non_sequential_token}"

        coupon = Coupon.new \
          code: coupon_name,
          discount: discount,
          duration: Coupon::FUN_DURATIONS.invert[duration],
          expires_at: expires_at,
          group: group,
          limit: 1,
          note: note,
          plan: plan

        begin
          Coupon.throttle { coupon.save! } unless dry_run
        rescue ActiveRecord::RecordInvalid
          log "There was an error saving the #{coupon_name} coupon."
          log "The errors were: #{coupon.errors.inspect}"
        end

        log coupon_name
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {
    count: 0
  }
  OptionParser.new do |opts|
    opts.on("-c", "--count COUNT", "number of coupons to create") do |count|
      options[:count] = count.to_i
    end

    opts.on("-p", "--prefix PREFIX", "prefix for generated coupons") do |prefix|
      options[:prefix] = prefix
    end

    opts.on("-n", "--note NOTE", "note to attach to each coupon") do |note|
      options[:note] = note
    end

    opts.on("-e", "--duration DURATION", "fun string format for the coupon duration e.g. (6 months)") do |duration|
      options[:duration] = duration
    end

    opts.on("-x", "--expires_at EXPIRES_AT", "string for the coupon expiration e.g. (2021-06-23 16:53:41 UTC)") do |expires_at|
      options[:expires_at] = expires_at
    end

    opts.on("-g", "--group GROUP", "group assigned to the coupon") do |group|
      options[:group] = group
    end

    opts.on("-u", "--discount DISCOUNT", "the discount for the coupon, 100% or 7.0") do |discount|
      options[:discount] = discount
    end

    opts.on("-r", "--plan PLAN", "the plan associated with the coupon: pro, business, or business_plus") do |plan|
      options[:plan] = plan
    end

    opts.on("-d", "--dry_run", "don't save or update any data, just log changes") do
      options[:dry_run] = true
    end
  end.parse!

  transition = GitHub::Transitions::BulkCouponGenerator.new
  transition.perform(**options)
end
