# Adapted from https://stackoverflow.com/a/54738882

RSpec::Matchers.define :match_model do |model1|
  match do |model2|
    ignored_columns = %w[id]

    model1.zip(model2).all? do |m1, m2|
      # Exclude ignored columns and only compare columns that are present in the model class
      # This removes columns added in JOINs that are not directly part of the model
      m1_attrs = m1.attributes.except(*ignored_columns).slice(*m1.class.column_names)
      m2_attrs = m2.attributes.except(*ignored_columns).slice(*m2.class.column_names)
      m1_attrs == m2_attrs
    end
  end
end
