# SQLiteREST

[![Version](https://img.shields.io/cocoapods/v/SQLiteREST.svg?style=flat)](https://cocoapods.org/pods/SQLiteREST)
[![License](https://img.shields.io/cocoapods/l/SQLiteREST.svg?style=flat)](https://cocoapods.org/pods/SQLiteREST)
[![Platform](https://img.shields.io/cocoapods/p/SQLiteREST.svg?style=flat)](https://cocoapods.org/pods/SQLiteREST)

A lightweight RESTful service for SQLite databases running on iOS devices. SQLiteREST provides a simple web UI that allows you to view and edit your device's SQLite database in real-time, making it extremely convenient for development and QA testing. No more manually exporting sandbox files to troubleshoot issues!

一个运行在 iOS 设备上的轻量级 SQLite RESTful 服务。SQLiteREST 提供了一个简单的 Web UI，让你可以实时查看和编辑设备上的 SQLite 数据库，这对于开发和 QA 测试来说非常方便。再也不用手动导出沙盒文件来排查问题了！

## Features

- 🚀 **RESTful API**: Access your SQLite database via HTTP endpoints
- 🌐 **Web UI**: Built-in web interface for browsing and editing database content
- 📱 **Real-time Access**: View and modify your database directly on the device
- 🔧 **Development Tool**: Perfect for debugging and QA testing
- 📦 **Easy Integration**: Simple CocoaPods installation
- 🔌 **Universal Compatibility**: Works with any SQLite3-based database

## Requirements

- iOS 13.0+
- Xcode 12.0+
- CocoaPods 1.10.0+

## UI

<table>
  <tr>
    <td style="text-align:center;">
      <img src="https://cdn.jsdelivr.net/gh/weirui-kong/SQLiteREST@main/demo_app.png" style="height:400px; object-fit:contain;" />
      <br/>App
    </td>
    <td style="text-align:center;">
      <img src="https://cdn.jsdelivr.net/gh/weirui-kong/SQLiteREST@main/demo_ui.png" style="height:400px; object-fit:contain;" />
      <br/>Web UI
    </td>
  </tr>
</table>

## Installation

SQLiteREST is available through [CocoaPods](https://cocoapods.org). To install it, simply add the following line to your `Podfile`:

```ruby
pod 'SQLiteREST'
```

Then run:

```bash
pod install
```

## Usage

### Basic Setup

1. Import the framework:

```swift
import SQLiteREST
```

2. Create and start the API server:

```swift
let server = SQLiteRESTAPIServer()

// Start the server on a port with your database path
let databasePath = // Your SQLite database file path
do {
    try server.start(databasePath: databasePath, port: 8080)
    print("SQLiteREST started at: \(server.serverURL?.absoluteString ?? "unknown")")
} catch {
    print("Failed to start SQLiteREST: \(error)")
}
```

3. Access:
   - Web UI: `http://<device-ip>:8080`
   - API Base: `http://<device-ip>:8080/api/v1`

### Example

The example project demonstrates how to use SQLiteREST with the [Northwind SQLite3 database](https://github.com/jpwhite3/northwind-SQLite3). To run the example:

1. Clone the repo
2. Run `pod install` from the Example directory
3. Open `Example/SQLiteREST.xcworkspace`
4. Build and run the app
5. Access the web UI at `http://<device-ip>:8080`

## ⚠️ Important Warnings

### Security Notice

**SQLiteREST is designed for development and testing purposes only. DO NOT use it in production builds.**

1. **Debug/Internal Testing Only**: Always ensure SQLiteREST is only included in debug or internal testing builds. Use conditional compilation to exclude it from release builds:

```swift
#if DEBUG
    let server = SQLiteRESTAPIServer()
    try? server.start(databasePath: databasePath, port: 8080)
#endif
```

2. **No Structured Query Validation**: The service does not perform structured query validation. Results may be incorrect, and **database corruption is possible**. 

3. **No Important Data**: **Never use SQLiteREST with databases containing important or sensitive data**. Always use test databases or ensure you have proper backups.

4. **Network Security**: The server runs on your local network without authentication. Make sure you're on a secure network when using this tool.

## API Documentation

For detailed API documentation, see [docs/api-v1.md](docs/api-v1.md).

## Demo Database

The example app uses the [Northwind SQLite3 database](https://github.com/jpwhite3/northwind-SQLite3) as a sample database to demonstrate SQLiteREST's capabilities. The Northwind database is a classic sample database that includes customers, orders, products, employees, and more.

## License

SQLiteREST is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
