import Foundation

struct AAMVAData: Equatable, Sendable {
    var licenseNumber: String?
    var lastName: String?
    var firstName: String?
    var middleName: String?
    var dateOfBirth: Date?
    var expirationDate: Date?
    var issueDate: Date?
    var under21Until: Date?
    var street: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var height: String?
    var eyeColor: String?
    var country: String?

    var displayName: String {
        [firstName, middleName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
