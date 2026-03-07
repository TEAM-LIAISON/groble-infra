#################################
# Required Variables
#################################

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (shared, dev, prod)"
  type        = string
}

variable "load_balancer_arn" {
  description = "ARN of the Application Load Balancer to associate with WAF"
  type        = string
}

#################################
# Geo-blocking Configuration
#################################

variable "allowed_country_codes" {
  description = "List of allowed country codes for geo-blocking"
  type        = list(string)
  default = [
    "KR", # South Korea
    "JP", # Japan
    "SG", # Singapore
    "AU", # Australia
    "NZ", # New Zealand
    "HK", # Hong Kong
    "TW", # Taiwan
    "TH", # Thailand
    "VN", # Vietnam
    "MY", # Malaysia
    "PH", # Philippines
    "ID", # Indonesia
    "IN"  # India
  ]
}

#################################
# Rate Limiting Configuration
#################################

variable "rate_limit_per_ip" {
  description = "Rate limit per IP address (requests per 5 minutes)"
  type        = number
  default     = 2000
}

variable "rate_limit_global" {
  description = "Global rate limit (requests per 5 minutes)"
  type        = number
  default     = 50000
}


variable "rate_limit_login_endpoints" {
  description = "Rate limit for login/auth endpoints (requests per 5 minutes)"
  type        = number
  default     = 50
}

#################################
# Request Size Configuration
#################################

variable "max_request_size" {
  description = "Maximum request body size in bytes (1MB = 1048576)"
  type        = number
  default     = 1048576
}

#################################
# Optional Variables
#################################

variable "custom_rules" {
  description = "List of custom WAF rules (for future expansion)"
  type        = list(any)
  default     = []
}