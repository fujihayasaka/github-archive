# Define a list of messages
messages = [
    "Hello! What's your name?",
    "Nice to meet you!",
    "Let's do some math. Enter a number:",
    "Now enter another number:",
    "Here's the sum:"
]

# Prompt the user and store responses
name = input(messages[0] + " ")
print(messages[1], name)

num1 = float(input(messages[2] + " "))
num2 = float(input(messages[3] + " "))

# Compute the sum and display it
print(messages[4], num1 + num2)
