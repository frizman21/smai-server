# Generic UI steps shared across features. Keep these few and unambiguous.

When("I click {string}") do |label|
  click_on label
end

Then("I should see {string}") do |text|
  expect(page).to have_content(text)
end
