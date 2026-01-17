# Contributing to Solid Queue Heroku Autoscaler

Thank you for your interest in contributing! This document outlines the process for contributing to this project.

## Development Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/solid_queue_autoscaler.git
   cd solid_queue_autoscaler
   ```
3. Install dependencies:
   ```bash
   bundle install
   ```
4. Run tests:
   ```bash
   bundle exec rspec
   ```
5. Run linter:
   ```bash
   bundle exec rubocop
   ```

## Pull Request Process

### 1. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

### 2. Make Your Changes

- Write tests for new functionality
- Ensure all tests pass: `bundle exec rspec`
- Ensure code passes linting: `bundle exec rubocop`
- Update documentation if needed

### 3. Commit Your Changes

Write clear, descriptive commit messages:

```bash
git commit -m "Add support for custom scaling algorithms"
```

### 4. Push and Create PR

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

### 5. PR Requirements

All PRs must:
- Pass all CI checks (tests on Ruby 3.1, 3.2, 3.3)
- Pass RuboCop linting
- Have at least 1 approval from a maintainer
- Be up to date with the main branch

### 6. Merging

Once approved and all checks pass, a maintainer will merge your PR.

## Release Process

Releases are automated via GitHub Actions when version changes are pushed to `main`.

### ✅ Correct Way to Release

1. **Bump the version** in `lib/solid_queue_autoscaler/version.rb`
2. **Update CHANGELOG.md** with the new version and changes
3. **Commit and push directly to main** (or merge a PR):
   ```bash
   git add -A
   git commit -m "Release vX.Y.Z: Brief description"
   git push origin main
   ```
4. The GitHub Actions workflow will automatically:
   - Run tests
   - Build and publish the gem to RubyGems.org
   - Create a GitHub Release with the version tag

### ⚠️ Do NOT Manually Create Tags Before Pushing

**Don't do this:**
```bash
# ❌ WRONG - creates tag before workflow runs
git tag -a v1.0.9 -m "Release v1.0.9"
git push origin v1.0.9
```

If you create the tag manually before the workflow runs, the "Create GitHub Release" step will fail with a 403 error because the tag already exists.

**The workflow creates the tag automatically** based on the version in `version.rb`.

### If You Accidentally Created a Tag First

If you pushed a tag before the workflow could create the release:

```bash
# Create the GitHub release manually
gh release create vX.Y.Z --title 'vX.Y.Z' --notes 'See CHANGELOG.md for details'
```

The gem will still be published to RubyGems (that step runs before the GitHub Release step).

### Version Numbering

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.0.0): Breaking changes
- **MINOR** (0.1.0): New features, backwards compatible
- **PATCH** (0.0.1): Bug fixes, backwards compatible

## Code Style

- Follow existing code patterns
- Use RuboCop for linting
- Write descriptive method and variable names
- Add comments for complex logic
- Keep methods focused and small

## Testing

- Write RSpec tests for all new functionality
- Aim for high test coverage
- Test edge cases and error conditions
- Use mocks/doubles for external services (Heroku API, Kubernetes API)

## Questions?

Open an issue if you have questions or need help!
