# frozen_string_literal: true

class AdditionalCVEReviewFields < ActiveRecord::Migration[5.2]
  def change
    # Part 1, correct some columns that were added before we were ready to use them
    #
    # remove the cve_ prefix from the cve_description.
    # Our new columns will not have the cve_ prefix, so to keep it this one column names this way would be inconsistent
    rename_column :cve_reviews, :cve_description, :description
    # the references column will be split into confirm reference, and misc_references
    remove_column :cve_reviews, :cve_references

    add_column :cve_reviews, :title, :string, limit: 140, null: true, default: nil
    # we already have the `description` column, thanks to above rename
    add_column :cve_reviews, :vendor_name,    :string, limit: 96, null: true, default: nil
    add_column :cve_reviews, :product,        :string, limit: 128, null: true, default: nil
    # serialized array of strings, each like ">= 2.0.0, < 2.3.4", or "before 1.2.3", or could be literally any string
    add_column :cve_reviews, :version_values, :mediumblob, null: true, default: nil
    # serialized array of strings, each like: "CWE-20: Improper Input Validation", though could be any string (does not have to be CWE)
    add_column :cve_reviews, :problemtype_values, :mediumblob, null: true, default: nil
    # confirm_reference should be URL of repo advisory.
    # 210 limit matches permalink in CVE Review (210 is max possible length for repo advisory url)
    add_column :cve_reviews, :confirm_reference, :string, limit: 210, null: true, default: nil
    # misc references is a serialized array of URLs, could be any length really
    add_column :cve_reviews, :misc_references, :mediumblob, null: true, default: nil

    # CVSS vector string will be a string like: CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:C/C:H/I:L/A:L
    # That example uses only Base metrics, which is probably all we should support really
    # a base metric string I think has max length of 44 chars.
    # BUT, if we supported temporal and environental metrics, then we could get a longer example like:
    #  CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:C/C:H/I:L/A:L/E:U/RL:T/RC:U/CR:H/IR:H/AR:H/MAV:L/MAC:L/MPR:L/MUI:R/MS:C/MC:H/MI:H/MA:H
    # the max length of cvss 3.1 vector string is 117 chars, I think.
    # therefore, the limit here will be 120 to future proof this column
    add_column :cve_reviews, :cvss_vectorString, :string, limit: 120, null: true, default: nil
  end
end
