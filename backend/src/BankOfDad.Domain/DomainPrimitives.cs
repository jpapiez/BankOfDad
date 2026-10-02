namespace BankOfDad.Domain;

public enum Role { Parent, Child }
public enum Frequency { Weekly, Biweekly, Monthly, Quarterly, Yearly }
public enum LoanStatus { Active, PaidOff, Cancelled }
public enum BillStatus { Active, Ended }
public enum InstallmentStatus { Upcoming, Due, Late, Paid }
public enum NotificationType { Reminder, Receipt, LoanCreated, LateFee, BillCreated }
public enum AllocationTarget { LateFee, Interest, Principal, Charge }
public enum EnrollmentKind { Bootstrap, Parent, Child }
public enum ChildCredentialKind { Password, Pin }

public static class Money
{
    public static decimal Round(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);
    public static string Format(decimal value, string currency = "USD") => value.ToString("C", System.Globalization.CultureInfo.GetCultureInfo("en-US"));
}
