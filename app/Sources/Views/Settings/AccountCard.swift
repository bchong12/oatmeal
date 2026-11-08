import SwiftUI

/// Settings › General: the account this copy of Oatmeal is connected to, its plan, and sign-in.
/// Hidden in the open-source build until a site connects it (`oatmeal://connect`).
struct AccountCard: View {
    @ObservedObject private var account = OatmealAccount.shared

    var body: some View {
        if let site = account.site {
            VStack(alignment: .leading, spacing: 10) {
                Text("ACCOUNT").font(DF.font(12, .bold)).tracking(1).foregroundStyle(DF.faint).padding(.top, 4)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        BrandMark(size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            if account.signedIn, let me = account.me {
                                HStack(spacing: 8) {
                                    Text(me.name ?? me.email ?? "Signed in").font(DF.font(15, .semibold))
                                    Text(me.planName).font(DF.font(11, .bold))
                                        .foregroundStyle(account.isPaid ? DF.ink : DF.muted)
                                        .padding(.horizontal, 7).frame(height: 20)
                                        .background(account.isPaid ? DF.honey : DF.wash, in: Capsule())
                                }
                                Text(account.isPaid ? "Every meeting, forever\(me.oatmealAI ? ", and Oatmeal AI" : "")"
                                     : "Your last \(me.historyDays ?? 30) days of meetings. Older ones unlock with Pro.")
                                    .font(DF.font(13)).foregroundStyle(DF.muted)
                            } else {
                                Text(account.signedIn ? "Checking your plan\u{2026}" : "Sign in to \(account.brand)").font(DF.font(15, .semibold))
                                Text("Connected to \(site.host ?? site.absoluteString)").font(DF.font(13)).foregroundStyle(DF.muted)
                            }
                        }
                        Spacer()
                        if account.busy { DFSpinner(size: 13, color: DF.muted) }
                        actions
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    if let error = account.error {
                        Rectangle().fill(DF.line).frame(height: 1).padding(.horizontal, 18)
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(DF.tiredInk)
                            Text(error).font(DF.font(13)).foregroundStyle(DF.muted).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Retry") { Task { await account.refresh() } }.buttonStyle(.df(.ghost, height: 26))
                        }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                    }
                }
                .dfCard()
            }
            .task { await account.refresh() }
        }
    }

    @ViewBuilder private var actions: some View {
        if !account.signedIn {
            Button("Sign in") { account.signIn() }.buttonStyle(.df(.primary))
        } else if account.me != nil {
            HStack(spacing: 6) {
                if !account.isPaid { Button("Upgrade to Pro") { account.openPricing() }.buttonStyle(.df(.honey, height: 30)) }
                Button { account.openAccountPage() } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.dfIcon(size: 30)).help("Your account on the web")
                Button("Sign out") { account.signOut() }.buttonStyle(.df(.ghost))
            }
        }
    }
}
