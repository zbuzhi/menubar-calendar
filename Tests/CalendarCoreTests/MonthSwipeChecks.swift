import Foundation
import CalendarCore

func checkMonthSwipes() {
    var swipe = MonthSwipe()
    XCTAssertEqual(swipe.update(x:0,y:0,phase:.began),.ignored)
    XCTAssertEqual(swipe.update(x:-3,y:1,phase:.changed),.ignored)
    XCTAssertEqual(swipe.update(x:-60,y:2,phase:.changed),.moved(-63))
    XCTAssertEqual(swipe.update(x:-4,y:0,phase:.ended),.finished(-67,cancelled:false))
    XCTAssertEqual(MonthSwipe.step(for:-67),1)
    for _ in 0..<20 {
        XCTAssertEqual(swipe.update(x:-80,y:0,phase:.changed,momentum:true),.consumed)
    }
    XCTAssertTrue(!swipe.isActive)
    XCTAssertEqual(swipe.update(x:70,y:0,phase:.began),.moved(70))
    XCTAssertEqual(swipe.update(x:0,y:0,phase:.ended),.finished(70,cancelled:false))
    XCTAssertEqual(MonthSwipe.step(for:70),-1)
    XCTAssertEqual(MonthSwipe.step(for:-900),1)
    XCTAssertEqual(MonthSwipe.step(for:51),0)
    XCTAssertEqual(MonthSwipe.step(for:-51),0)

    // A vertical gesture remains vertical even if it drifts sideways later.
    XCTAssertEqual(swipe.update(x:2,y:8,phase:.began),.ignored)
    XCTAssertEqual(swipe.update(x:180,y:0,phase:.changed),.ignored)
    XCTAssertEqual(swipe.update(x:0,y:0,phase:.ended),.ignored)
    XCTAssertEqual(swipe.update(x:30,y:30,phase:.changed,momentum:true),.ignored)
    XCTAssertEqual(swipe.update(x:80,y:1,phase:.began),.moved(80))
    XCTAssertEqual(swipe.update(x:0,y:0,phase:.cancelled),.finished(80,cancelled:true))
    XCTAssertEqual(swipe.update(x:0,y:0,phase:.ended),.ignored)
    // Reversing direction within the same gesture can return below the paging threshold.
    XCTAssertEqual(swipe.update(x:-90,y:0,phase:.began),.moved(-90))
    XCTAssertEqual(swipe.update(x:75,y:0,phase:.changed),.moved(-15))
    XCTAssertEqual(swipe.update(x:0,y:0,phase:.ended),.finished(-15,cancelled:false))
    XCTAssertEqual(MonthSwipe.step(for:-15),0)
    swipe.reset()
    XCTAssertTrue(!swipe.capturesMomentum)
    print("Checked: month swipe axis locking, reversal, cancellation, thresholds and momentum isolation")
}
