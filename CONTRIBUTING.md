# Contributing to Swift-MQTT

You are welcome to submit any bugs, issues and feature requests on this repository. This guide explains how to effectively collaborate on our MQTT client implementation for Swift.

## 1. Code of Conduct

All participants must adhere to our [Code of Conduct](.github/CODE_OF_CONDUCT.md).

## 2. Development Workflow

### a. Reporting Issues

- Search existing [Issues](https://gitbub.com/emqx/swift-mqtt/issues) first
- Use template:

```markdown
### Environment
- Swift Version: 
- Platform: 

### Problem Description
[Concise summary]

### Expected Behavior
[Clear expectation]

### Reproduction Steps
1. 
2. 
3. 


b. Pull Requests

1. Branch naming: feature/[short-description] or fix/[issue-number]

2. Implementation requirements:

  ◦ 100% passing tests (swift test)

  ◦ Updated documentation for API changes

  ◦ Compatibility with Swift 5.9+

3. Commit message format:

[Type]: [Brief description]

- Detail 1
- Detail 2

Resolves #IssueNumber


Types: feat, fix, docs, test, chore

3. Code Standards

• Swift-specific:
```swift
// 4-space indentation
struct MQTTConfig {
    let host: String
    func connect() async throws {
        guard isValid else { 
            throw MQTTError.invalidConfig 
        }
    }
}
```

• Avoid force unwrapping (!)

• Prefer protocol-oriented design

4. Testing

swift test --enable-test-discovery


