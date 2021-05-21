//
//  main.swift
//
//
//  Created by 方泓睿 on 2021/5/19.
//

import CGlfw
import CVulkan
import Foundation

glfwInit()

glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)

let glfwWindow = glfwCreateWindow(800, 600, "Vulkan Window", nil, nil)

precondition(glfwWindow != nil, "failed to create glfw window")

var extensionCount: UInt32 = 0

vkEnumerateInstanceExtensionProperties(nil, &extensionCount, nil)

while glfwWindowShouldClose(glfwWindow) == 0 {
    glfwPollEvents()
}

glfwDestroyWindow(glfwWindow)

glfwTerminate()
