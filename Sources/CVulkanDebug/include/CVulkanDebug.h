//
//  CVulkanDebug.h
//  
//
//  Created by 方泓睿 on 2021/5/21.
//

#ifndef CVulkanDebug_h
#define CVulkanDebug_h

#include <vulkan/vulkan.h>

void populateDebugMessengerCreateInfo(VkDebugUtilsMessengerCreateInfoEXT* createInfo);

VkResult createDebugUtilsMessengerEXT(VkInstance instance, const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDebugUtilsMessengerEXT* pDebugMessenger);

void destroyDebugUtilsMessengerEXT(VkInstance instance, VkDebugUtilsMessengerEXT debugMessenger, const VkAllocationCallbacks* pAllocator);

#endif /* CVulkanDebug_h */
