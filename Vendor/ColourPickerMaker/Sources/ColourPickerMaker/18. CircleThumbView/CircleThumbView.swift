//  CircleThumbView.swift
//  ColourPickerMaker
//
//  Created by Rob Sturgeon on 09/06/2020.
//  Copyright © 2020 Rob Sturgeon. All rights reserved.
//
//  Released under the MIT license
//  https://sturdysturge.com/mit/

import SwiftUI

public struct CircleThumbView {
  public init(size: CGFloat) {
    self.size = size
  }
  
    let size: CGFloat
}

extension CircleThumbView: View {
  public var body: some View {
        ZStack {
            // Lines patch: a thin white ring with a soft shadow.
            Circle()
                .strokeBorder(.white, lineWidth: 3)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
                .frame(width: self.size, height: self.size)
        }
    }
}

struct CircleThumbView_Previews: PreviewProvider {
    static var previews: some View {
        CircleThumbView(size: 25)
    }
}
