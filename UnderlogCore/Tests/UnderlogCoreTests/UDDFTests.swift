import Foundation
import Testing
@testable import UnderlogCore

@Suite("UDDF import and export")
struct UDDFTests {
    let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <uddf version="3.2.0" xmlns="http://www.streit.cc/uddf/3.2/">
      <gasdefinitions>
        <mix id="ean32"><name>EAN32</name><o2>0.32</o2><n2>0.68</n2><he>0.0</he></mix>
      </gasdefinitions>
      <diver>
        <owner id="me"><personal><firstname>H</firstname></personal></owner>
        <buddy id="b1"><personal><firstname>Anna</firstname><lastname>Kovács</lastname></personal></buddy>
      </diver>
      <divesite>
        <site id="s1"><name>Molnár János Cave</name>
          <geography><latitude>47.5183</latitude><longitude>19.0366</longitude></geography>
        </site>
      </divesite>
      <profiledata>
        <repetitiongroup id="rg">
          <dive id="d1">
            <informationbeforedive>
              <link ref="s1"/><link ref="b1"/>
              <datetime>2026-08-15T10:30:00</datetime>
              <divenumber>87</divenumber>
            </informationbeforedive>
            <tankdata>
              <link ref="ean32"/>
              <tankvolume>0.012</tankvolume>
              <tankpressurebegin>20000000</tankpressurebegin>
              <tankpressureend>6000000</tankpressureend>
            </tankdata>
            <samples>
              <waypoint><divemode type="opencircuit"/><depth>0</depth><divetime>0</divetime><temperature>299.15</temperature></waypoint>
              <waypoint><depth>12.5</depth><divetime>120</divetime><temperature>297.15</temperature></waypoint>
              <waypoint><depth>14.0</depth><divetime>1800</divetime></waypoint>
              <waypoint><depth>0</depth><divetime>2400</divetime></waypoint>
            </samples>
            <informationafterdive>
              <greatestdepth>14.0</greatestdepth>
              <diveduration>2400</diveduration>
              <notes><para>Warm water &amp; good visibility.</para><para>Saw the old line.</para></notes>
              <rating><ratingvalue>9</ratingvalue></rating>
            </informationafterdive>
          </dive>
        </repetitiongroup>
      </profiledata>
    </uddf>
    """

    @Test func importsADive() throws {
        let dives = try UDDFImporter.importDives(from: Data(sample.utf8))
        #expect(dives.count == 1)
        let dive = try #require(dives.first)
        #expect(dive.diveNumber == 87)
        #expect(dive.maxDepth == 14)
        #expect(dive.duration == 2400)
        #expect(dive.site?.name == "Molnár János Cave")
        #expect(abs((dive.site?.latitude ?? 0) - 47.5183) < 1e-9)
        #expect(dive.buddies == ["Anna Kovács"])
        #expect(dive.cylinders.count == 1)
        #expect(dive.cylinders[0].gas == GasMix(oxygen: 0.32))
        #expect(abs((dive.cylinders[0].volumeLiters ?? 0) - 12) < 1e-9)
        #expect(dive.cylinders[0].startPressureBar == 200)
        #expect(dive.cylinders[0].endPressureBar == 60)
        #expect(dive.samples.count == 4)
        #expect(abs((dive.minTemperature ?? 0) - 24) < 1e-9)
        #expect(dive.notes == "Warm water & good visibility.\n\nSaw the old line.")
        #expect(dive.rating == 5)
        #expect(dive.mode == .openCircuit)
    }

    @Test func rejectsOtherXML() {
        #expect(throws: UDDFImporter.ImportError.notUDDF) {
            try UDDFImporter.importDives(from: Data("<gpx><trk/></gpx>".utf8))
        }
    }

    @Test func rejectsUDDFWithoutDives() {
        #expect(throws: UDDFImporter.ImportError.noDives) {
            try UDDFImporter.importDives(from: Data("<uddf version=\"3.2.0\"><profiledata/></uddf>".utf8))
        }
    }

    @Test func exportThenImportKeepsTheDive() throws {
        let original = try #require(UDDFImporter.importDives(from: Data(sample.utf8)).first)
        let exported = UDDFExporter.export([original])
        let reimported = try #require(UDDFImporter.importDives(from: exported).first)

        #expect(abs(reimported.startDate.timeIntervalSince(original.startDate)) < 1)
        #expect(reimported.diveNumber == original.diveNumber)
        #expect(reimported.maxDepth == original.maxDepth)
        #expect(reimported.duration == original.duration)
        #expect(reimported.site == original.site)
        #expect(reimported.buddies == original.buddies)
        #expect(reimported.cylinders == original.cylinders)
        #expect(reimported.notes == original.notes)
        #expect(reimported.rating == original.rating)
        #expect(reimported.samples.count == original.samples.count)
        for (a, b) in zip(reimported.samples, original.samples) {
            #expect(a.time == b.time)
            #expect(a.depth == b.depth)
            #expect(abs((a.temperature ?? 0) - (b.temperature ?? 0)) < 1e-6)
        }
    }

    @Test func exportEscapesText() throws {
        let dive = ImportedDive(startDate: Date(), duration: 60, maxDepth: 3, notes: "<b>bold</b> & \"quoted\"")
        let reimported = try #require(UDDFImporter.importDives(from: UDDFExporter.export([dive])).first)
        #expect(reimported.notes == "<b>bold</b> & \"quoted\"")
    }

    @Test func freediveModeSurvivesRoundTrip() throws {
        let dive = ImportedDive(
            startDate: Date(), duration: 90, maxDepth: 15, mode: .freedive,
            samples: [DiveSample(time: 0, depth: 0), DiveSample(time: 45, depth: 15), DiveSample(time: 90, depth: 0)]
        )
        let reimported = try #require(UDDFImporter.importDives(from: UDDFExporter.export([dive])).first)
        #expect(reimported.mode == .freedive)
    }
}
