# How to Create Cohorts Manually

Since the onboarding tool is internal, Engineers and Product Managers using the page will need to manually create cohorts within the [billing_platform_onboarding_cohort.rb](https://github.com/github/github/blob/master/packages/billing/app/models/billing/billing_platform_onboarding_cohort.rb) model.

## Table of Contents

- [Details](#details)
  - [Defining the Cohort](#defining-the-cohort)
  - [Function Descriptions](#function-descriptions)

## Details
A cohort should be defined by Customer IDs. These Customer IDs are sent into the `customers_info_for_cohort(customer_ids)` method to produce a Hash of information about the corhort that includes `customer_ids`, `total_customers` (a count of the customer ids), and `onboarded_customers` (a count of the customers from this cohort that have been onboarded).

The current model has example cohorts that are defined as a collection of Business IDs and their respective Customer IDs within each Business. For the purpose of allowing more complex cohort definitions, each cohort is represented/separated by function, for example, self.onboard_customers_cohort_1 represents cohort 1 and self.onboard_customers_cohort_2 represents cohort 2, etc.

### Defining the Cohort

| Function | Modification |
|--------|--------|
| `self.onboard_customers_cohort_*` | Create a new function with this format where the * is substitued with the Cohort ID you're defining. Within the function, define your cohort in a way where the Customer ID's you want are queried.|
| `self.onboard_customers_cohort(cohort_id)`| Add a case for the new cohort you just defined.  |

Creating onboard_customers_cohort_4 to define a cohort as a collection of Businesses and their respective Customer IDs.
```ruby
def self.onboard_customers_cohort_4
      customer_ids = Business.where(staff_owned: true).limit(3).pluck(:customer_id)
      customers_info_for_cohort(customer_ids)
    end
```
Modifying onboard_customers_cohort to allow cohort_id = 4
```ruby
when 4
        onboard_customers_cohort_4
```

Remember to update the `self.total_cohorts` value to reflect the new count of corhorts.

### Function Descriptions

| Function | Description |
|--------|--------|
| `self.check_onboarding_status_for_cohort(customers)` | Checks if customers have already been onboarded to vNext |
| `self.customers_info_for_cohort(customer_ids)` | Returns all relevant cohort information after retrieving customers and determining onboarding status |
| `self.total_cohorts` | Returns a count of the total number of cohorts in the model |
