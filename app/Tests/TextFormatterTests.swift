import XCTest
@testable import Dayform

final class TextFormatterTests: XCTestCase {
    private let o = TextFormatter.Options(words: [DictionaryWord(heard: "supabase", written: "Supabase"), DictionaryWord(heard: "day form", written: "Dayform")],
                                          snippets: [Snippet(cue: "my calendar link", text: "https://cal.com/branden")])
    private func f(_ s: String, _ k: TextFormatter.AppKind = .standard) -> String { TextFormatter.format(s, app: k, options: o) }

    func testFillers() { XCTAssertEqual(f("Um, so I think we should, uh, ship it on Friday."), "So I think we should ship it on Friday.") }
    func testOnlyFiller() { XCTAssertEqual(f("um"), "") }
    func testBacktrackTime() { XCTAssertEqual(f("Let's meet at 2, actually 3 tomorrow."), "Let's meet at 3 tomorrow.") }
    func testBacktrackDay() { XCTAssertEqual(f("Book the room for Tuesday, no wait Wednesday."), "Book the room for Wednesday.") }
    func testScratchThat() { XCTAssertEqual(f("Send the deck to Priya. Scratch that. Send it to Sam."), "Send it to Sam.") }
    func testSpokenPunctuation() { XCTAssertEqual(f("Hey comma can you check this question mark"), "Hey, can you check this?") }
    func testNumberedList() { XCTAssertEqual(f("Groceries: first milk, second eggs, third bread."), "Groceries:\n1. Milk\n2. Eggs\n3. Bread") }
    func testOneInSentenceIsNotAList() { XCTAssertEqual(f("One thing I noticed is the header."), "One thing I noticed is the header.") }
    func testSnippetInline() { XCTAssertEqual(f("Here is my calendar link if you want to book."), "Here is https://cal.com/branden if you want to book.") }
    func testSnippetAlone() { XCTAssertEqual(f("my calendar link"), "https://cal.com/branden") }
    func testDictionary() { XCTAssertEqual(f("We moved the backend to supabase and day form."), "We moved the backend to Supabase and Dayform.") }
    func testLinksUntouched() { XCTAssertEqual(f("check example.com and email me at sam@acme.io"), "Check example.com and email me at sam@acme.io") }
    func testCasualDropsFullStop() { XCTAssertEqual(f("sounds good see you there.", .casual), "Sounds good see you there") }
    func testCodeCase() { XCTAssertEqual(f("rename it to camel case user profile view and run the tests.", .code), "Rename it to userProfileView and run the tests") }
    func testNoDoubleMark() { XCTAssertEqual(f("Hey comma can you check this question mark?"), "Hey, can you check this?") }
    func testPM() { XCTAssertEqual(f("Call mom tomorrow at 5 p.m. for half an hour."), "Call mom tomorrow at 5 pm for half an hour.") }
    func testNumbersStay() { XCTAssertEqual(f("I read 20 pages today."), "I read 20 pages today.") }
    func testNewLines() { XCTAssertEqual(f("new line dear sam new paragraph thanks"), "Dear sam\n\nThanks") }
    func testAppKind() {
        XCTAssertEqual(TextFormatter.kind(for: "com.apple.MobileSMS"), .casual)
        XCTAssertEqual(TextFormatter.kind(for: "dev.warp.Warp-Stable"), .code)
        XCTAssertEqual(TextFormatter.kind(for: "com.apple.Notes"), .standard)
    }
}

final class NextWeekdayTests: XCTestCase {
    func testNextMondayFromSaturdayIsTwoDaysAway() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 17; c.hour = 10   // Saturday
        let sat = Calendar.dayform.date(from: c)!
        let d = QuickAddParser.nextDate(weekday: 2, from: sat, forceNextWeek: true)
        XCTAssertEqual(Calendar.dayform.dateComponents([.day], from: Calendar.dayform.startOfDay(for: sat), to: d).day, 2)
    }
}
