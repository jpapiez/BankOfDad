import SwiftUI

struct KidLoanDetailView: View {
    let loanId: UUID
    var body: some View { LoanDetailView(loanId: loanId, isKidMode: true) }
}
