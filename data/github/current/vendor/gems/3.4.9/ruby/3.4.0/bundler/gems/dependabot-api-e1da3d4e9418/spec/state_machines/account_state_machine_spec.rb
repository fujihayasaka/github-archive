# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountStateMachine do
  let(:account) { FactoryBot.create(:account) }

  describe "guards" do
    describe "to active" do
      context "with an installation_id" do
        it "can transition" do
          metadata = { installation_id: 123 }
          expect { account.transition_to!(:active, metadata) }.
            not_to raise_error
        end

        context "when re-activating an account" do
          context "that has been used before" do
            before do
              account.transition_to!(:active, installation_id: 123)
              account.transition_to!(:inactive, installation_id: 123)
            end

            it "can transition" do
              metadata = { installation_id: 123 }
              expect { account.transition_to!(:active, metadata) }.
                not_to raise_error
            end
          end

          context "that has not been used before" do
            before do
              account.transition_to!(:active, installation_id: 122)
              account.transition_to!(:inactive, installation_id: 122)
            end

            it "can transition" do
              metadata = { installation_id: 123 }
              expect { account.transition_to!(:active, metadata) }.
                not_to raise_error
            end
          end
        end
      end

      context "without an installation_id" do
        it "can't transition" do
          expect { account.transition_to!(:active) }.
            to raise_error(Statesman::GuardFailedError)
        end
      end
    end

    describe "to inactive" do
      before { account.transition_to!(:active, installation_id: 123) }

      context "with a matching installation_id" do
        it "can transition" do
          expect { account.transition_to!(:inactive, installation_id: 123) }.
            not_to raise_error
        end
      end

      context "without an installation_id" do
        it "can't transition" do
          expect { account.transition_to!(:inactive) }.
            to raise_error(Statesman::GuardFailedError)
        end
      end

      context "with a non-matching installation_id" do
        it "can't transition" do
          expect { account.transition_to!(:inactive, installation_id: 124) }.
            to raise_error(Statesman::GuardFailedError)
        end
      end
    end
  end
end
