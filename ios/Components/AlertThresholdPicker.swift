import SwiftUI

struct AlertThresholdPicker: View {
    let title: String
    let description: String
    let options: [Int]
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker(title, selection: $value) {
                ForEach(options, id: \.self) { hours in
                    Text("\(hours) hours").tag(hours)
                }
            }
            .pickerStyle(.segmented)

            Stepper("Custom: \(value) hours", value: $value, in: 1...72)
                .font(.subheadline)
        }
        .padding(.vertical, 6)
    }
}
