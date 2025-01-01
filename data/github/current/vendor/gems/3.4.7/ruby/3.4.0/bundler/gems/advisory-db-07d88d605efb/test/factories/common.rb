# frozen_string_literal: true

FactoryBot.define do
  # Common description string to be used across any uses of description. Has unicode characters to surface unicode bugs.
  factory :description, class: "String" do
    initialize_with do
      "Aut molestiae sunt. Et odit assumenda. 😇 Voluptas quos accusamus ’ .\n\nNihil aut sunt. Accusamus aliquid ut. Aspernatur rerum voluptatum.\n\nExercitationem sit aliquam. Consequatur quos dolore. Temporibus numquam quasi.\n\nTempora nostrum est. Et dolores sed. Exercitationem qui eos.\n\nQuos quia nobis. Molestiae cum fugiat. Vitae velit cum.\n\nEx laboriosam quibusdam. Ut aut totam. Exercitationem voluptas dolor.\n\nPraesentium aut eaque. Et hic illum. Maxime laboriosam et.\n\nRem ut consequatur. Aliquam qui ea. Optio voluptas maiores.\n\nAt dolorem iure. Culpa veniam vel. Consectetur repellendus officia.\n\nCorporis saepe vel. In eum officia. Voluptatem aut maiores."
    end
  end

  # Common summary string to be used across any uses of summary.
  # Summary stores a varchar(255) and seems to be unicode unfriendly
  factory :summary, class: "String" do
    initialize_with do
      "Optio cupiditate et totam quidem ipsum corporis sunt quas ut dignissimos vero quo voluptas voluptatum corrupti quod veniam illo consequatur."
    end
  end
end
