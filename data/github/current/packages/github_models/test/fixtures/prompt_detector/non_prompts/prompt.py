# Prompt the user for two numbers
num1 = float(prompt := input("Prompt: Enter the first number: "))
num2 = float(prompt := input("Prompt: Enter the second number: "))

# Compute the sum of the two numbers
result = num1 + num2

# Display the result with a prompt
print(prompt := f"Prompt: The sum is {result}")
