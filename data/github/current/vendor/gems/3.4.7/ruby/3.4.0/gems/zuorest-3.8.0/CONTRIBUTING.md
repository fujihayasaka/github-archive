# Contributing to Zuorest

Thank you for considering contributing to Zuorest! Here are some guidelines to help you get started.

## Code Style

This project uses [RuboCop](https://github.com/rubocop/rubocop) with the [GitHub Ruby style guide](https://github.com/github/rubocop-github) to enforce consistent code style.

To check your code:

```
bundle exec rake rubocop
```

## Development Process

1. Fork the repository and create your branch from `master`.
2. Install dependencies with `bundle install`.
3. Make your changes and add tests for your changes.
4. Ensure the test suite passes: `bundle exec rake test`.
5. Make sure your code passes the style checks: `bundle exec rake rubocop`.
6. Submit a pull request.

## Testing

Run tests with:

```
bundle exec rake test
```

## License

By contributing to Zuorest, you agree that your contributions will be licensed under the project's license.