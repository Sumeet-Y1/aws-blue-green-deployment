package com.devops.aws_blue_green_deployment;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class AppController {

    private static final String VERSION = "v6";

    @GetMapping("/hello")
    public Map<String, String> hello() {
        Map<String, String> response = new HashMap<>();
        try {
            response.put("version", VERSION);
            response.put("message", "Hello from Blue-Green Deployment!");
            response.put("server", InetAddress.getLocalHost().getHostName());
            response.put("timestamp", LocalDateTime.now().toString());
            response.put("status", "healthy");
        } catch (Exception e) {
            response.put("error", e.getMessage());
        }
        return response;
    }

    @GetMapping("/version")
    public Map<String, String> version() {
        Map<String, String> response = new HashMap<>();
        response.put("version", VERSION);
        response.put("environment", System.getenv().getOrDefault("ENVIRONMENT", "blue"));
        return response;
    }
}