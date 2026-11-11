#if os(macOS)
import CoinboxCore
import SwiftUI

/// A month looking back: what each category spent next to what the following month has set aside.
/// Categories the next month looks short on carry a gold mark; clicking a row shows where the money went and offers to plan for it.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var month = MonthKey.current().previous
    @State private var expanded: Set<String> = []

    var body: some View {
        let review = model.review(month)
        VStack(spacing: 0) {
            header(review)
            Divider().overlay(Theme.line)
            ScrollView {
                if let review {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(review.groups, id: \.groupID) { group($0, total: review.spent) }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
            }
        }
        .background(Theme.background)
    }

    private var next: MonthKey { month.next }

    /// Short by at least $25, and not because this month was a one-off.
    private func isShort(_ c: CategoryReview) -> Bool { c.planGap <= -25_000 && !unusual(c) }

    /// Spending well above the three-month average reads as a one-off, not a pace to plan for.
    private func unusual(_ c: CategoryReview) -> Bool { c.averageSpent > 0 && c.spent > c.averageSpent * 18 / 10 }

    // MARK: header

    private func header(_ r: MonthReview?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button { month = month.previous } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Text(month.name).font(.title2.weight(.semibold))
                Button { month = month.next } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                Spacer()
                if let r {
                    figure("In", r.income, Theme.text)
                    figure("Out", r.spent, Theme.text)
                    figure("Net", r.income - r.spent, r.income >= r.spent ? Theme.done : Theme.danger)
                }
            }
            if let r {
                let short = r.groups.flatMap(\.categories).filter(isShort)
                Text(short.isEmpty
                     ? "\(next.name)'s plan covers \(month.name)'s spending."
                     : "\(next.name)'s plan is \(Money.format(-short.reduce(0) { $0 + $1.planGap })) under \(month.name)'s spending in \(short.count) categories, marked below.")
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16).background(Theme.bar)
    }

    private func figure(_ title: String, _ amount: Milliunits, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(Theme.dim)
            Text(Money.format(amount)).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
        .padding(.leading, 24)
    }

    // MARK: groups

    private func group(_ g: GroupReview, total: Milliunits) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(g.name).font(.headline)
                Spacer()
                Text(month.name).frame(width: 110, alignment: .trailing)
                Text(next.name).frame(width: 110, alignment: .trailing)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.dim).padding(.bottom, 6)
            ForEach(g.categories, id: \.categoryID) { row($0) }
            Divider().overlay(Theme.line).padding(.top, 2)
            HStack {
                Text(total > 0 && g.spent > 0 ? "\(Int((Double(g.spent) / Double(total) * 100).rounded()))% of spending" : "").font(.caption).foregroundStyle(Theme.faint)
                Spacer()
                Text(Money.format(g.spent)).frame(width: 110, alignment: .trailing)
                Text(Money.format(g.nextAssigned)).frame(width: 110, alignment: .trailing)
            }
            .font(.callout.weight(.semibold)).monospacedDigit().padding(.top, 6)
        }
    }

    @ViewBuilder private func row(_ c: CategoryReview) -> some View {
        let open = expanded.contains(c.categoryID)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappyUI) { if open { expanded.remove(c.categoryID) } else { expanded.insert(c.categoryID) } }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(isShort(c) ? Theme.gold : .clear).frame(width: 6, height: 6)
                    Text(c.name).lineLimit(1)
                    Spacer()
                    Text(Money.format(c.spent)).foregroundStyle(c.spent == 0 ? Theme.faint : Theme.text).frame(width: 110, alignment: .trailing)
                    Text(Money.format(c.nextFunded)).foregroundStyle(isShort(c) ? Theme.gold : c.nextFunded == 0 ? Theme.faint : Theme.text).frame(width: 110, alignment: .trailing)
                }
                .monospacedDigit().padding(.vertical, 5).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(open ? RoundedRectangle(cornerRadius: 6).fill(Theme.card).padding(.horizontal, -8) : nil)
            if open { details(c).appears(from: .top) }
        }
    }

    private func details(_ c: CategoryReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(unusual(c) ? "Usually \(Money.format(c.averageSpent)) a month; \(month.name) looks like a one-off." : "Usually \(Money.format(c.averageSpent)) a month.")
                .foregroundStyle(Theme.dim)
            ForEach(c.topPayees, id: \.name) { p in
                HStack {
                    Text(p.name).lineLimit(1)
                    if p.count > 1 { Text("×\(p.count)").foregroundStyle(Theme.faint) }
                    Spacer()
                    Text(Money.format(p.spent)).monospacedDigit()
                }
                .foregroundStyle(Theme.dim)
            }
            if c.planGap < 0 {
                HStack(spacing: 8) {
                    Spacer()
                    if c.averageSpent > c.nextFunded && c.averageSpent < c.spent {
                        Button("Plan \(Money.format(c.averageSpent)) (usual)") { cover(c, to: c.averageSpent) }.buttonStyle(.bordered)
                    }
                    Button("Plan \(Money.format(c.spent)) (\(month.name))") { cover(c, to: c.spent) }.buttonStyle(.bordered)
                }
            }
        }
        .font(.callout).padding(.leading, 14).padding(.vertical, 8)
    }

    /// Raises the next month's assignment so the category has `amount` set aside there.
    private func cover(_ c: CategoryReview, to amount: Milliunits) {
        guard amount > c.nextFunded else { return }
        model.setAssigned(c.categoryID, month: next, c.nextAssigned + amount - c.nextFunded)
    }
}

extension MonthKey {
    /// "October", or "October 2025" outside this year.
    var name: String {
        let full = title
        return year == MonthKey.current().year ? String(full.split(separator: " ").first ?? "") : full
    }
}
#endif
