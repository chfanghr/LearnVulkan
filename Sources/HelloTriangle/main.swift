//
//  main.swift
//
//
//  Created by 方泓睿 on 2021/5/17.
//

import Foundation

#if DEBUG
    let enableValidation = true
#else
    let enableValidation = false
#endif

do {
    let app = try Application(enableValidation: enableValidation)
    try app.run()
} catch {
    print("unexpected error: \(error)")
}
