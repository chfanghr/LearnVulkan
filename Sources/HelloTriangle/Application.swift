//
//  Application.swift
//
//
//  Created by 方泓睿 on 2021/5/20.
//

import CGlfw
import CVulkan
import CVulkanDebug
import Dispatch
import Foundation
import Utilities

public class Application {
    public init(enableValidation: Bool = true, width: Int32 = 800, height: Int32 = 600, name: String = "Hello Trigangle") throws {
        self.enableValidation = enableValidation
        self.name = name

        try initWindow(width: width, height: height)
        try initVulkan()
    }

    public func run() throws {
        try mainLoop()
    }

    deinit {
        cleanup()
    }

    public enum Error: Swift.Error {
        case failedToCreateWindow
        case validationLayersUnavailable
        case failedToCreateInstance
        case failedToSetupDebugMessenger
        case failedToCreateWindowSurface
        case noVulkanDevice
        case noSuitableDevice
        case failedToCreateDevice
        case failedToCreateSwapchain
        case failedToCreateImageView
        case failedToCreateShaderModule
        case failedToCreatePipelineLayout
        case failedToCreateRenderPass
        case failedToCreateGraphicsPipeline
        case failedToCreateFramebuffer
        case failedToCreateCommandPool
        case failedToAllocateCommandBuffers
        case failedToBeginRecordingCommandBuffer
        case failedToRecordCommandBuffer
        case failedToCreateSynchronizationObjects
        case failedToSubmitDrawCommandBuffer
    }

    public let name: String
    private let enableValidation: Bool

    private var window: OpaquePointer!

    private var instance: VkInstance!

    private var debugMessenger: VkDebugUtilsMessengerEXT!

    private var surface: VkSurfaceKHR!

    private var phyDevice: VkPhysicalDevice!
    private var device: VkDevice!

    private var graphicsQueue, presentQueue: VkQueue!

    private var swapchain: VkSwapchainKHR!
    private var swapchainImages: [VkImage?] = []
    private var swapchainImageViews: [VkImageView?] = []
    private var swapchainImageFormat: VkFormat = .init(rawValue: 0)
    private var swapchainExtent: VkExtent2D = .init()

    private var renderPass: VkRenderPass!
    private var pipelineLayout: VkPipelineLayout!

    private var graphicsPipeline: VkPipeline!

    private var swapchainFramebuffers: [VkFramebuffer?] = []

    private var commandPool: VkCommandPool!
    private var commandBuffers: [VkCommandBuffer?] = []

    private var imageAvailableSemaphores: [VkSemaphore?] = []
    private var renderFinishedSemaphores: [VkSemaphore?] = []

    private var inFlightFences: [VkFence?] = []
    private var imagesInFlight: [VkFence?] = []

    private static let validationLayers = ["VK_LAYER_KHRONOS_validation"]
    private static let deviceExtensions = [VK_KHR_SWAPCHAIN_EXTENSION_NAME]

    private static let vertShaderUrl: URL = Bundle.module.url(forResource: "vert", withExtension: "spv")!
    private static let fragShaderUrl: URL = Bundle.module.url(forResource: "frag", withExtension: "spv")!

    private static var fileDataCache: [URL: Data] = [:]

    private static let maxFramesInFlight = 5

    private var currentFrame = 0

    private func initWindow(width: Int32, height: Int32) throws {
        glfwInit()

        glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
        glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)

        window = glfwCreateWindow(Int32(width), Int32(height), name, nil, nil)
        guard window != nil else {
            throw Error.failedToCreateWindow
        }
    }

    private func initVulkan() throws {
        try createInstance()
        try setupDebugMessenger()
        try createSurface()
        try pickPhysicalDevice()
        try createLogicalDevice()
        try createSwapchain()
        try createImageViews()
        try createRenderPass()
        try createGraphicsPipeline()
        try createFramebuffers()
        try createCommandPool()
        try createCommandBuffers()
        try createSyncObjects()
    }

    private func mainLoop() throws {
        let dispatchQueue = DispatchQueue(label: "hellowTriangle.drawFrame", qos: .userInteractive)
        let jobCount = SharedWrapper<UInt64>(0)

        while glfwWindowShouldClose(window) == 0 {
            glfwPollEvents()
            dispatchQueue.async {
                if jobCount.value >= 5 { return }

                jobCount.value += 1

                do {
                    try self.drawFrame()
                } catch {
                    print("warning: failed to draw frame: \(error)")
                }

                jobCount.value -= 1
            }
        }

        vkDeviceWaitIdle(device)
    }

    private func cleanup() {
        destroySyncObjects()
        vkDestroyCommandPool(device, commandPool, nil)
        destroyFramebuffers()
        vkDestroyPipeline(device, graphicsPipeline, nil)
        vkDestroyPipelineLayout(device, pipelineLayout, nil)
        vkDestroyRenderPass(device, renderPass, nil)
        destroySwapchainImageViews()
        vkDestroySwapchainKHR(device, swapchain, nil)
        vkDestroyDevice(device, nil)
        vkDestroySurfaceKHR(instance, surface, nil)
        deinitDebugMessenger()
        vkDestroyInstance(instance, nil)

        glfwDestroyWindow(window)
        glfwTerminate()
    }

    private func createInstance() throws {
        if enableValidation, !Self.checkValidationLayerSupport() {
            throw Error.validationLayersUnavailable
        }

        var appInfo = VkApplicationInfo()
        appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
        appInfo.apiVersion = vkApiVersion10
        appInfo.pApplicationName = swiftStringToCConstString(name)
        defer { freeCConstString(appInfo.pApplicationName) }

        var createInfo = VkInstanceCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        createInfo.pApplicationInfo = .init(&appInfo)

        var extensions = swiftStringsToCConstStringArray(getRequiredExtensions())
        defer { freeCConstStringArray(extensions) }
        createInfo.enabledExtensionCount = UInt32(extensions.count)
        createInfo.ppEnabledExtensionNames = .init(&extensions)

        var layers = swiftStringsToCConstStringArray(Self.validationLayers)
        defer { freeCConstStringArray(layers) }

        var debugCreateInfo = VkDebugUtilsMessengerCreateInfoEXT()

        if enableValidation {
            createInfo.enabledLayerCount = UInt32(layers.count)
            createInfo.ppEnabledLayerNames = .init(&layers)

            populateDebugMessengerCreateInfo(&debugCreateInfo)
            createInfo.pNext = .init(&debugCreateInfo)
        } else {
            createInfo.enabledLayerCount = 0
            createInfo.ppEnabledLayerNames = nil
        }

        if vkCreateInstance(&createInfo, nil, &instance) != VK_SUCCESS {
            throw Error.failedToCreateInstance
        }
    }

    private func setupDebugMessenger() throws {
        guard enableValidation else { return }

        var createInfo = VkDebugUtilsMessengerCreateInfoEXT()
        populateDebugMessengerCreateInfo(&createInfo)

        guard createDebugUtilsMessengerEXT(instance, &createInfo, nil, &debugMessenger) == VK_SUCCESS else {
            throw Error.failedToSetupDebugMessenger
        }
    }

    private func createSurface() throws {
        guard glfwCreateWindowSurface(instance, window, nil, &surface) == VK_SUCCESS else {
            throw Error.failedToCreateWindowSurface
        }
    }

    private func pickPhysicalDevice() throws {
        var deviceCount: UInt32 = 0
        vkEnumeratePhysicalDevices(instance, &deviceCount, nil)

        guard deviceCount != 0 else {
            throw Error.noVulkanDevice
        }

        var devices = [VkPhysicalDevice?](repeating: nil, count: Int(deviceCount))
        vkEnumeratePhysicalDevices(instance, &deviceCount, &devices)

        var highestScore = invalidScore

        for device in devices {
            let score = rateDevice(device: device)
            if score > highestScore {
                highestScore = score
                phyDevice = device
            }
        }

        guard phyDevice != nil else {
            throw Error.noSuitableDevice
        }

        showPhysicalDeviceBeingUsed()
    }

    private func createLogicalDevice() throws {
        let indices = findQueueFamily(of: phyDevice)

        var queueCreateInfos: [VkDeviceQueueCreateInfo] = []
        let uniqueQueueFamily: Set<UInt32> = [indices.graphicsFamily!, indices.presentFamily!]

        var queuePriority: Float32 = 1.0

        for queueFamily in uniqueQueueFamily {
            var queueCreateInfo = VkDeviceQueueCreateInfo()
            queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
            queueCreateInfo.queueFamilyIndex = queueFamily
            queueCreateInfo.queueCount = 1
            queueCreateInfo.pQueuePriorities = .init(&queuePriority)

            queueCreateInfos.append(queueCreateInfo)
        }

        var deviceFeatures = VkPhysicalDeviceFeatures()

        var createInfo = VkDeviceCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO

        createInfo.queueCreateInfoCount = UInt32(queueCreateInfos.count)
        createInfo.pQueueCreateInfos = .init(&queueCreateInfos)

        createInfo.pEnabledFeatures = .init(&deviceFeatures)

        var extensions = Self.deviceExtensions
        if hasPortabilitySetExtension(device: phyDevice) {
            extensions.append(portabilitySubsetExtensionName)
        }

        var extensionCNames = swiftStringsToCConstStringArray(extensions)
        var validationLayerCNames = swiftStringsToCConstStringArray(Self.validationLayers)
        defer {
            freeCConstStringArray(extensionCNames)
            freeCConstStringArray(validationLayerCNames)
        }

        createInfo.enabledExtensionCount = UInt32(extensions.count)
        createInfo.ppEnabledExtensionNames = .init(&extensionCNames)

        if enableValidation {
            createInfo.enabledLayerCount = UInt32(Self.validationLayers.count)
            createInfo.ppEnabledLayerNames = .init(&validationLayerCNames)
        } else {
            createInfo.enabledLayerCount = 0
        }

        guard vkCreateDevice(phyDevice, &createInfo, nil, &device) == VK_SUCCESS else {
            throw Error.failedToCreateDevice
        }

        vkGetDeviceQueue(device, indices.graphicsFamily!, 0, &graphicsQueue)
        vkGetDeviceQueue(device, indices.presentFamily!, 0, &presentQueue)
    }

    private func createSwapchain() throws {
        let swapchainSupport = querySwapchainSupport(of: phyDevice)

        let surfaceFormat = swapchainSupport.preferedFormat
        let presentMode = swapchainSupport.preferedPresentMode
        let extent = chooseSwapExtent(swapchainSupport)

        var imageCount = swapchainSupport.capabilities.minImageCount + 1
        if swapchainSupport.capabilities.maxImageCount != 0 {
            imageCount = clamp(imageCount, in: swapchainSupport.capabilities.minImageCount ... swapchainSupport.capabilities.maxImageCount)
        }

        var createInfo = VkSwapchainCreateInfoKHR()
        createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
        createInfo.surface = surface

        createInfo.minImageCount = imageCount
        createInfo.imageArrayLayers = 1
        createInfo.imageFormat = surfaceFormat.format
        createInfo.imageColorSpace = surfaceFormat.colorSpace
        createInfo.imageExtent = extent
        createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue

        createInfo.preTransform = swapchainSupport.capabilities.currentTransform

        createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR

        createInfo.presentMode = presentMode
        createInfo.clipped = VK_TRUE

        createInfo.oldSwapchain = nil

        let indices = findQueueFamily(of: phyDevice)
        var queueFamilyIndices = [indices.graphicsFamily!, indices.presentFamily!]

        if indices.graphicsFamily! == indices.presentFamily! {
            createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE
        } else {
            createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT
            createInfo.queueFamilyIndexCount = 2
            createInfo.pQueueFamilyIndices = .init(&queueFamilyIndices)
        }

        guard vkCreateSwapchainKHR(device, &createInfo, nil, &swapchain) == VK_SUCCESS else {
            throw Error.failedToCreateSwapchain
        }

        imageCount = 0
        vkGetSwapchainImagesKHR(device, swapchain, &imageCount, nil)
        swapchainImages = .init(repeating: nil, count: Int(imageCount))
        vkGetSwapchainImagesKHR(device, swapchain, &imageCount, &swapchainImages)

        swapchainImageFormat = surfaceFormat.format
        swapchainExtent = extent
    }

    private func createImageViews() throws {
        swapchainImageViews = .init(repeating: nil, count: swapchainImages.count)

        for (i, image) in swapchainImages.enumerated() {
            var createInfo = VkImageViewCreateInfo()
            createInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
            createInfo.image = image

            createInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY
            createInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY
            createInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY
            createInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY

            createInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
            createInfo.format = swapchainImageFormat

            createInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT.rawValue
            createInfo.subresourceRange.baseMipLevel = 0
            createInfo.subresourceRange.levelCount = 1
            createInfo.subresourceRange.baseArrayLayer = 0
            createInfo.subresourceRange.layerCount = 1

            guard vkCreateImageView(device, &createInfo, nil, &swapchainImageViews[i]) == VK_SUCCESS else {
                throw Error.failedToCreateImageView
            }
        }
    }

    private func createRenderPass() throws {
        var colorAttachment = VkAttachmentDescription()
        colorAttachment.format = swapchainImageFormat
        colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT

        colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE

        colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE

        colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR

        var colorAttachmentRef = VkAttachmentReference()
        colorAttachmentRef.attachment = 0
        colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL

        var subpass = VkSubpassDescription()
        subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS

        subpass.colorAttachmentCount = 1
        subpass.pColorAttachments = .init(&colorAttachmentRef)

        var dependency = VkSubpassDependency()
        dependency.srcSubpass = VK_SUBPASS_EXTERNAL
        dependency.dstSubpass = 0

        dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue
        dependency.srcAccessMask = 0

        dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue
        dependency.dstStageMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue

        var createInfo = VkRenderPassCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO

        createInfo.attachmentCount = 1
        createInfo.pAttachments = .init(&colorAttachment)

        createInfo.subpassCount = 1
        createInfo.pSubpasses = .init(&subpass)

        createInfo.dependencyCount = 1
        createInfo.pDependencies = .init(&dependency)

        guard vkCreateRenderPass(device, &createInfo, nil, &renderPass) == VK_SUCCESS else {
            throw Error.failedToCreateRenderPass
        }
    }

    private func createGraphicsPipeline() throws {
        let vertShaderCode = try Self.readFile(Self.vertShaderUrl)
        let fragShaderCode = try Self.readFile(Self.fragShaderUrl)

        let vertShaderModule = try createShaderModule(from: vertShaderCode)
        let fragShaderModule = try createShaderModule(from: fragShaderCode)

        let mainCName = swiftStringToCConstString("main")
        defer { freeCConstString(mainCName) }

        var vertShaderStageCreateInfo = VkPipelineShaderStageCreateInfo()
        vertShaderStageCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        vertShaderStageCreateInfo.stage = VK_SHADER_STAGE_VERTEX_BIT
        vertShaderStageCreateInfo.module = vertShaderModule
        vertShaderStageCreateInfo.pName = mainCName

        var fragShaderStageCreateInfo = VkPipelineShaderStageCreateInfo()
        fragShaderStageCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        fragShaderStageCreateInfo.stage = VK_SHADER_STAGE_FRAGMENT_BIT
        fragShaderStageCreateInfo.module = fragShaderModule
        fragShaderStageCreateInfo.pName = mainCName

        var shaderStages = [vertShaderStageCreateInfo, fragShaderStageCreateInfo]

        var vertexInputStateCreateInfo = VkPipelineVertexInputStateCreateInfo()
        vertexInputStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
        vertexInputStateCreateInfo.vertexBindingDescriptionCount = 0
        vertexInputStateCreateInfo.vertexAttributeDescriptionCount = 0

        var inputAssemblyStateCreateInfo = VkPipelineInputAssemblyStateCreateInfo()
        inputAssemblyStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
        inputAssemblyStateCreateInfo.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        inputAssemblyStateCreateInfo.primitiveRestartEnable = VK_FALSE

        var viewport = VkViewport()
        viewport.x = 0
        viewport.y = 0
        viewport.width = Float(swapchainExtent.width)
        viewport.height = Float(swapchainExtent.height)
        viewport.minDepth = 0
        viewport.maxDepth = 1

        var scissor = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: swapchainExtent)

        var viewportStateCreateInfo = VkPipelineViewportStateCreateInfo()
        viewportStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
        viewportStateCreateInfo.viewportCount = 1
        viewportStateCreateInfo.pViewports = .init(&viewport)
        viewportStateCreateInfo.scissorCount = 1
        viewportStateCreateInfo.pScissors = .init(&scissor)

        var rasterizerCreateInfo = VkPipelineRasterizationStateCreateInfo()
        rasterizerCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        rasterizerCreateInfo.depthClampEnable = VK_FALSE

        rasterizerCreateInfo.rasterizerDiscardEnable = VK_FALSE

        rasterizerCreateInfo.polygonMode = VK_POLYGON_MODE_FILL

        rasterizerCreateInfo.lineWidth = 1

        rasterizerCreateInfo.cullMode = VK_CULL_MODE_BACK_BIT.rawValue
        rasterizerCreateInfo.frontFace = VK_FRONT_FACE_CLOCKWISE

        rasterizerCreateInfo.depthBiasEnable = VK_FALSE

        var multiSamplingCreateInfo = VkPipelineMultisampleStateCreateInfo()
        multiSamplingCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        multiSamplingCreateInfo.sampleShadingEnable = VK_FALSE
        multiSamplingCreateInfo.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT

        var colorBlendAttachment = VkPipelineColorBlendAttachmentState()
        colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT.rawValue | VK_COLOR_COMPONENT_G_BIT.rawValue | VK_COLOR_COMPONENT_B_BIT.rawValue | VK_COLOR_COMPONENT_A_BIT.rawValue
        colorBlendAttachment.blendEnable = VK_FALSE

        var colorBlendingCreateInfo = VkPipelineColorBlendStateCreateInfo()
        colorBlendingCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
        colorBlendingCreateInfo.logicOpEnable = VK_FALSE
        colorBlendingCreateInfo.attachmentCount = 1
        colorBlendingCreateInfo.pAttachments = .init(&colorBlendAttachment)

        var dynamicStates = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_LINE_WIDTH]

        var dynamicStateCreateInfo = VkPipelineDynamicStateCreateInfo()
        dynamicStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
        dynamicStateCreateInfo.dynamicStateCount = 2
        dynamicStateCreateInfo.pDynamicStates = .init(&dynamicStates)

        // TODO: - not finished yet

        var pipelineLayoutCreateInfo = VkPipelineLayoutCreateInfo()
        pipelineLayoutCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
        pipelineLayoutCreateInfo.setLayoutCount = 0
        pipelineLayoutCreateInfo.pSetLayouts = nil
        pipelineLayoutCreateInfo.pushConstantRangeCount = 0
        pipelineLayoutCreateInfo.pPushConstantRanges = nil

        guard vkCreatePipelineLayout(device, &pipelineLayoutCreateInfo, nil, &pipelineLayout) == VK_SUCCESS else {
            throw Error.failedToCreatePipelineLayout
        }

        var pipelineCreateInfo = VkGraphicsPipelineCreateInfo()
        pipelineCreateInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
        pipelineCreateInfo.pVertexInputState = .init(&vertexInputStateCreateInfo)
        pipelineCreateInfo.pInputAssemblyState = .init(&inputAssemblyStateCreateInfo)
        pipelineCreateInfo.pViewportState = .init(&viewportStateCreateInfo)
        pipelineCreateInfo.pRasterizationState = .init(&rasterizerCreateInfo)
        pipelineCreateInfo.pMultisampleState = .init(&multiSamplingCreateInfo)
        pipelineCreateInfo.pDepthStencilState = nil
        pipelineCreateInfo.pColorBlendState = .init(&colorBlendingCreateInfo)
        pipelineCreateInfo.layout = pipelineLayout
        pipelineCreateInfo.renderPass = renderPass
        pipelineCreateInfo.subpass = 0
        pipelineCreateInfo.stageCount = 2
        pipelineCreateInfo.pStages = .init(&shaderStages)

        guard vkCreateGraphicsPipelines(device, nil, 1, &pipelineCreateInfo, nil, &graphicsPipeline) == VK_SUCCESS else {
            throw Error.failedToCreateGraphicsPipeline
        }
    }

    private func createFramebuffers() throws {
        swapchainFramebuffers = .init(repeating: nil, count: swapchainImages.count)

        for (i, imageView) in swapchainImageViews.enumerated() {
            var attchments = [imageView]

            var framebufferInfo = VkFramebufferCreateInfo()
            framebufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
            framebufferInfo.renderPass = renderPass
            framebufferInfo.attachmentCount = 1
            framebufferInfo.pAttachments = .init(&attchments)
            framebufferInfo.width = swapchainExtent.width
            framebufferInfo.height = swapchainExtent.height
            framebufferInfo.layers = 1

            guard vkCreateFramebuffer(device, &framebufferInfo, nil, &swapchainFramebuffers[i]) == VK_SUCCESS else {
                throw Error.failedToCreateFramebuffer
            }
        }
    }

    private func createCommandPool() throws {
        let queueFamilyIndices = findQueueFamily(of: phyDevice)

        var poolInfo = VkCommandPoolCreateInfo()
        poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
        poolInfo.queueFamilyIndex = queueFamilyIndices.graphicsFamily!
        poolInfo.flags = 0

        guard vkCreateCommandPool(device, &poolInfo, nil, &commandPool) == VK_SUCCESS else {
            throw Error.failedToCreateCommandPool
        }
    }

    private func createCommandBuffers() throws {
        commandBuffers = .init(repeating: nil, count: swapchainFramebuffers.count)

        var allocInfo = VkCommandBufferAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        allocInfo.commandPool = commandPool
        allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        allocInfo.commandBufferCount = UInt32(commandBuffers.count)

        guard vkAllocateCommandBuffers(device, &allocInfo, &commandBuffers) == VK_SUCCESS else {
            throw Error.failedToAllocateCommandBuffers
        }

        for (i, commandBuffer) in commandBuffers.enumerated() {
            var beginInfo = VkCommandBufferBeginInfo()
            beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO

            guard vkBeginCommandBuffer(commandBuffer, &beginInfo) == VK_SUCCESS else {
                throw Error.failedToBeginRecordingCommandBuffer
            }

            var renderPassBeginInfo = VkRenderPassBeginInfo()
            renderPassBeginInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
            renderPassBeginInfo.renderPass = renderPass
            renderPassBeginInfo.framebuffer = swapchainFramebuffers[i]
            renderPassBeginInfo.renderArea.offset = .init(x: 0, y: 0)
            renderPassBeginInfo.renderArea.extent = swapchainExtent

            var clearColor = VkClearValue(color: .init(float32: (0, 0, 0, 1)))
            renderPassBeginInfo.clearValueCount = 1
            renderPassBeginInfo.pClearValues = .init(&clearColor)

            vkCmdBeginRenderPass(commandBuffer, &renderPassBeginInfo, VK_SUBPASS_CONTENTS_INLINE)

            vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline)

            vkCmdDraw(commandBuffer, 3, 1, 0, 0)

            vkCmdEndRenderPass(commandBuffer)

            guard vkEndCommandBuffer(commandBuffer) == VK_SUCCESS else {
                throw Error.failedToRecordCommandBuffer
            }
        }
    }

    private func createSyncObjects() throws {
        var semaphoresInfo = VkSemaphoreCreateInfo()
        semaphoresInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO

        var fenceInfo = VkFenceCreateInfo()
        fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
        fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT.rawValue

        imageAvailableSemaphores = .init(repeating: nil, count: Self.maxFramesInFlight)
        renderFinishedSemaphores = .init(repeating: nil, count: Self.maxFramesInFlight)
        inFlightFences = .init(repeating: nil, count: Self.maxFramesInFlight)
        imagesInFlight = .init(repeating: nil, count: swapchainImages.count)

        for i in 0 ..< Self.maxFramesInFlight {
            guard vkCreateSemaphore(device, &semaphoresInfo, nil, &imageAvailableSemaphores[i]) == VK_SUCCESS,
                  vkCreateSemaphore(device, &semaphoresInfo, nil, &renderFinishedSemaphores[i]) == VK_SUCCESS,
                  vkCreateFence(device, &fenceInfo, nil, &inFlightFences[i]) == VK_SUCCESS
            else {
                throw Error.failedToCreateSynchronizationObjects
            }
        }
    }

    private func drawFrame() throws {
        vkWaitForFences(device, 1, &inFlightFences[currentFrame], VK_TRUE, UInt64.max)
        vkResetFences(device, 1, &inFlightFences[currentFrame])

        var imageIndex: UInt32 = 0
        vkAcquireNextImageKHR(device, swapchain, UInt64.max, imageAvailableSemaphores[currentFrame], nil, &imageIndex)

        if imagesInFlight[Int(imageIndex)] != nil {
            vkWaitForFences(device, 1, &imagesInFlight[Int(imageIndex)], VK_TRUE, UInt64.max)
        }

        imagesInFlight[Int(imageIndex)] = inFlightFences[currentFrame]

        var submitInfo = VkSubmitInfo()
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO

        var waitSemaphores = [imageAvailableSemaphores[currentFrame]]
        var waitStages: [VkPipelineStageFlags] = [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue]

        submitInfo.waitSemaphoreCount = 1
        submitInfo.pWaitSemaphores = .init(&waitSemaphores)
        submitInfo.pWaitDstStageMask = .init(&waitStages)

        submitInfo.commandBufferCount = 1
        submitInfo.pCommandBuffers = .init(&commandBuffers[Int(imageIndex)])

        var signalSemaphores = [renderFinishedSemaphores[currentFrame]]

        submitInfo.signalSemaphoreCount = 1
        submitInfo.pSignalSemaphores = .init(&signalSemaphores)

        vkResetFences(device, 1, &inFlightFences[currentFrame])

        guard vkQueueSubmit(graphicsQueue, 1, &submitInfo, inFlightFences[currentFrame]) == VK_SUCCESS else {
            throw Error.failedToSubmitDrawCommandBuffer
        }

        var presentInfo = VkPresentInfoKHR()
        presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR

        presentInfo.waitSemaphoreCount = 1
        presentInfo.pWaitSemaphores = .init(&signalSemaphores)

        var swapchains = [swapchain]

        presentInfo.swapchainCount = 1
        presentInfo.pSwapchains = .init(&swapchains)
        presentInfo.pImageIndices = .init(&imageIndex)

        presentInfo.pResults = nil

        vkQueuePresentKHR(presentQueue, &presentInfo)

        currentFrame = (currentFrame + 1) % Self.maxFramesInFlight
    }

    private func deinitDebugMessenger() {
        if enableValidation {
            destroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
        }
    }

    private func getRequiredExtensions() -> [String] {
        var glfwExtensionCount: UInt32 = 0
        let glfwExtensionsPP = glfwGetRequiredInstanceExtensions(&glfwExtensionCount)

        var glfwExtensions = cConstStringArrayToSwiftStrings(glfwExtensionsPP, count: glfwExtensionCount)

        if enableValidation {
            glfwExtensions.append(VK_EXT_DEBUG_UTILS_EXTENSION_NAME)
        }

        // According to https://github.com/KhronosGroup/MoltenVK/issues/1363,
        //  `VK_KHR_get_physical_device_properties2` is an instance extension.
        glfwExtensions.append("VK_KHR_get_physical_device_properties2")

        return glfwExtensions
    }

    private static func checkValidationLayerSupport() -> Bool {
        var layerCount: UInt32 = 0
        vkEnumerateInstanceLayerProperties(&layerCount, nil)

        var availableLayers = [VkLayerProperties](repeating: VkLayerProperties(), count: Int(layerCount))
        vkEnumerateInstanceLayerProperties(&layerCount, &availableLayers)

        var requiredLayerSet = Set(Self.validationLayers)

        for layer in availableLayers {
            requiredLayerSet.remove(toString(layer.layerName))
        }

        return requiredLayerSet.isEmpty
    }

    private let invalidScore = -1

    private func rateDevice(device: VkPhysicalDevice!) -> Int {
        var score = 0

        guard findQueueFamily(of: device).isComplete,
              checkDeviceExtensionSupport(of: device),
              querySwapchainSupport(of: device).isAdequate
        else {
            return invalidScore
        }

        var deviceProperties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(device, &deviceProperties)

        var deviceFeatures = VkPhysicalDeviceFeatures()
        vkGetPhysicalDeviceFeatures(device, &deviceFeatures)

        if deviceProperties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU {
            score += 1000
        }

        return score
    }

    private struct QueueFamilyIndices {
        var graphicsFamily: UInt32?
        var presentFamily: UInt32?

        var isComplete: Bool {
            graphicsFamily != nil && presentFamily != nil
        }
    }

    private func findQueueFamily(of device: VkPhysicalDevice!) -> QueueFamilyIndices {
        var indices = QueueFamilyIndices()

        var queueFamilyCount: UInt32 = 0
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nil)

        var queueFamilies = [VkQueueFamilyProperties](repeating: VkQueueFamilyProperties(), count: Int(queueFamilyCount))
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, &queueFamilies)

        for (i, queueFamily) in queueFamilies.enumerated() {
            if (queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT.rawValue) != 0 {
                indices.graphicsFamily = UInt32(i)
            }

            var presentSupport: VkBool32 = VK_FALSE
            vkGetPhysicalDeviceSurfaceSupportKHR(device, UInt32(i), surface, &presentSupport)

            if presentSupport == VK_TRUE {
                indices.presentFamily = UInt32(i)
            }

            if indices.isComplete {
                break
            }
        }

        return indices
    }

    private func checkDeviceExtensionSupport(of device: VkPhysicalDevice!) -> Bool {
        var extensionCount: UInt32 = 0
        vkEnumerateDeviceExtensionProperties(device, nil, &extensionCount, nil)

        var extensions = [VkExtensionProperties](repeating: VkExtensionProperties(), count: Int(extensionCount))
        vkEnumerateDeviceExtensionProperties(device, nil, &extensionCount, &extensions)

        var requiredExtensions = Set(Self.deviceExtensions)

        extensions.forEach { requiredExtensions.remove(toString($0.extensionName)) }

        return requiredExtensions.isEmpty
    }

    struct SwapchainSupportDetails {
        var capabilities: VkSurfaceCapabilitiesKHR = .init()
        var formats: [VkSurfaceFormatKHR] = []
        var presentModes: [VkPresentModeKHR] = []

        var isAdequate: Bool {
            !(formats.isEmpty || presentModes.isEmpty)
        }

        var preferedFormat: VkSurfaceFormatKHR {
            formats.first { $0.format == VK_FORMAT_B8G8R8_SRGB && $0.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR } ?? formats.first!
        }

        var preferedPresentMode: VkPresentModeKHR {
            presentModes.first { $0 == VK_PRESENT_MODE_MAILBOX_KHR } ?? presentModes.first!
        }
    }

    private func chooseSwapExtent(_ details: SwapchainSupportDetails) -> VkExtent2D {
        if details.capabilities.currentExtent.width != UInt32.max {
            return details.capabilities.currentExtent
        }

        var width: Int32 = 0, height: Int32 = 0
        glfwGetFramebufferSize(window, &width, &height)

        return VkExtent2D(
            width: clamp(UInt32(width), in: details.capabilities.minImageExtent.width ... details.capabilities.maxImageExtent.width),
            height: clamp(UInt32(height), in: details.capabilities.minImageExtent.height ... details.capabilities.maxImageExtent.height)
        )
    }

    private func querySwapchainSupport(of device: VkPhysicalDevice!) -> SwapchainSupportDetails {
        var details = SwapchainSupportDetails()

        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities)

        var formatCount: UInt32 = 0
        vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, nil)
        if formatCount > 0 {
            details.formats = .init(repeating: VkSurfaceFormatKHR(), count: Int(formatCount))
            vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, &details.formats)
        }

        var modeCount: UInt32 = 0
        vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &modeCount, nil)
        if modeCount > 0 {
            details.presentModes = .init(repeating: VkPresentModeKHR(0), count: Int(modeCount))
            vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &modeCount, &details.presentModes)
        }

        return details
    }

    private static func deviceTypeName(_ deviceType: VkPhysicalDeviceType) -> String {
        switch deviceType {
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:
            return "Discrete GPU"
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:
            return "Integrated GPU"
        case VK_PHYSICAL_DEVICE_TYPE_CPU:
            return "CPU"
        default:
            return "unknown"
        }
    }

    private func showPhysicalDeviceBeingUsed() {
        var deviceProperties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(phyDevice, &deviceProperties)

        print("info: using physical device \(toString(deviceProperties.deviceName)) (\(Self.deviceTypeName(deviceProperties.deviceType)))")
    }

    let portabilitySubsetExtensionName = "VK_KHR_portability_subset"

    private func hasPortabilitySetExtension(device: VkPhysicalDevice!) -> Bool {
        var extensionCount: UInt32 = 0
        vkEnumerateDeviceExtensionProperties(device, nil, &extensionCount, nil)

        var extensions = [VkExtensionProperties](repeating: VkExtensionProperties(), count: Int(extensionCount))
        vkEnumerateDeviceExtensionProperties(device, nil, &extensionCount, &extensions)

        return extensions.first { toString($0.extensionName) == portabilitySubsetExtensionName } != nil
    }

    private func destroySwapchainImageViews() {
        for imageView in swapchainImageViews {
            vkDestroyImageView(device, imageView, nil)
        }
    }

    private static func readFile(_ url: URL) throws -> Data {
        if let data = fileDataCache[url] {
            return data
        }

        let data = try Data(contentsOf: url)
        fileDataCache[url] = data
        return data
    }

    private func createShaderModule(from code: Data) throws -> VkShaderModule! {
        try code.withUnsafeBytes { ptr in
            var createInfo = VkShaderModuleCreateInfo()
            createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
            createInfo.codeSize = code.count
            createInfo.pCode = ptr.baseAddress!.assumingMemoryBound(to: UInt32.self)

            var shaderModule: VkShaderModule!
            guard vkCreateShaderModule(device, &createInfo, nil, &shaderModule) == VK_SUCCESS else {
                throw Error.failedToCreateShaderModule
            }

            return shaderModule
        }
    }

    private func destroyFramebuffers() {
        for framebuffer in swapchainFramebuffers {
            vkDestroyFramebuffer(device, framebuffer, nil)
        }
    }

    private func destroySyncObjects() {
        for i in 0 ..< Self.maxFramesInFlight {
            vkDestroySemaphore(device, imageAvailableSemaphores[i], nil)
            vkDestroySemaphore(device, renderFinishedSemaphores[i], nil)
            vkDestroyFence(device, inFlightFences[i], nil)
        }
    }
}
