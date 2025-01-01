# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces::Locations
  class RegionLocatorTest < GitHub::TestCase
    include DogstatsTestHelpers

    TEST_LOCATIONS = [
      {
        name: "Nairobi",
        location: { latitude: -1.286389, longitude: 36.817222 },
        expected: "CentralIndia",
      },
      {
        name: "Boston",
        location: { latitude: 42.358056, longitude: -71.063611 },
        expected: "EastUs",
      },
      {
        name: "Missoula",
        location: { latitude: 46.8625, longitude: -114.011667 },
        expected: "WestUs2",
      },
      {
        name: "New Delhi",
        location: { latitude: 28.613895, longitude: 77.209006 },
        expected: "CentralIndia",
      },
    ]

    fixtures do
      @user = create(:user)
    end

    context "from_ip_location_lookup" do
      TEST_LOCATIONS.each do |l|
        test "users in #{l[:name]} should be routed to #{l[:expected]} based on passed client ip" do
          user = create(:user)

          GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(l[:location])

          loc = Codespaces::Locations::RegionLocator.new(user, client_ip: "1.2.3.4")

          assert_equal l[:expected], loc.from_ip_location_lookup
        end
      end

      TEST_LOCATIONS.each do |l|
        test "users in #{l[:name]} should be routed to #{l[:expected]} based on their request ip" do
          user = create(:user)

          GitHub.context.push(actor_ip: "1.2.3.4")

          GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(l[:location])

          loc = Codespaces::Locations::RegionLocator.new(user)

          assert_equal l[:expected], loc.from_ip_location_lookup
        end
      end


      TEST_LOCATIONS.each do |l|
        test "users in #{l[:name]} should be routed to #{l[:expected]} after falling back to auth record" do
          user = create(:user)

          good_ip = "1.2.3.4"
          missing_ip = "4.3.2.1"

          create(:authentication_record, user: user, ip_address: good_ip)

          GitHub.context.push(actor_ip: missing_ip)

          GitHub::Location.expects(:look_up).with(good_ip).returns(l[:location])
          GitHub::Location.expects(:look_up).with(missing_ip).returns({})

          loc = Codespaces::Locations::RegionLocator.new(user)

          assert_equal l[:expected], loc.from_ip_location_lookup
        end
      end

      TEST_LOCATIONS.each do |l|
        test "users in #{l[:name]} should be routed to #{l[:expected]} after falling back to much older auth record" do
          user = create(:user)
          good_ip = "1.2.3.4"
          missing_ip = "4.3.2.1"

          create(:authentication_record, user: user, ip_address: good_ip)

          4.times do
            create(:authentication_record, user: user, ip_address: missing_ip)
          end

          GitHub.context.push(actor_ip: missing_ip)

          GitHub::Location.expects(:look_up).times(1).with(good_ip).returns(l[:location])
          GitHub::Location.expects(:look_up).times(5).with(missing_ip).returns({})

          loc = Codespaces::Locations::RegionLocator.new(user)
          assert_equal l[:expected], loc.from_ip_location_lookup
        end
      end

      context "with only a subset of locations available" do
        test "uses the next-closest location" do
          user = create(:user)
          missoula = TEST_LOCATIONS.find { |l| l[:name] == "Missoula" }

          GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(missoula[:location])

          loc = Codespaces::Locations::RegionLocator.new(user, client_ip: "1.2.3.4")
          location_list = Codespaces::Locations::Region.where(vscs_target: Codespaces::Vscs.default_target).map(&:id) - ["WestUs2"]

          assert_equal "WestUs3", loc.from_ip_location_lookup(locations: location_list)
        end
      end

      context "with no locations available" do
        test "returns nil" do
          user = create(:user)
          missoula = TEST_LOCATIONS.find { |l| l[:name] == "Missoula" }

          GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(missoula[:location])

          loc = Codespaces::Locations::RegionLocator.new(user, client_ip: "1.2.3.4")

          assert_nil loc.from_ip_location_lookup(locations: [])
        end
      end

      context "invalid maxmind or auth locations" do
        test "no maxmind response returns nil" do
          user = create(:user)

          GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(nil)
          GitHub::Location.stubs(:look_up).with(nil).returns(nil)

          loc = Codespaces::Locations::RegionLocator.new(user, client_ip: "1.2.3.4")
          assert_nil loc.from_ip_location_lookup
        end

        test "invalid maxmind response returns nil" do
          user = create(:user)

          GitHub::Location.stubs(:look_up).with("1.2.3.4").returns({ latitude: 97.213, longitude: nil })
          GitHub::Location.stubs(:look_up).with(nil).returns(nil)

          loc = Codespaces::Locations::RegionLocator.new(user, client_ip: "1.2.3.4")
          assert_nil loc.from_ip_location_lookup
        end
      end
    end
  end
end
