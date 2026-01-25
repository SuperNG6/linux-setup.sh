// ========================================
// Terminal Typing Animation
// ========================================
const terminalCommand = '/bin/bash <(wget -qO - https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/server-setup.sh)';
const typedCommandElement = document.getElementById('typed-command');
const terminalOutputElement = document.getElementById('terminal-output');

let charIndex = 0;
let typingSpeed = 80;

function typeCommand() {
    if (charIndex < terminalCommand.length) {
        typedCommandElement.textContent += terminalCommand.charAt(charIndex);
        charIndex++;
        setTimeout(typeCommand, typingSpeed);
    } else {
        // After typing, show output
        setTimeout(showTerminalOutput, 800);
    }
}

function showTerminalOutput() {
    const outputLines = [
        '✓ 检测到操作系统: Ubuntu 22.04',
        '✓ 防火墙类型: ufw',
        '✓ 地理位置: CN (使用国内镜像)',
        '',
        '========================================',
        '     Linux 服务器自动化配置工具',
        '========================================',
        '',
        '1.  安装 Docker',
        '2.  配置 Fail2ban',
        '3.  优化内核参数',
        '4.  安装 XanMod 内核',
        '5.  配置防火墙',
        '...',
        '',
        '请选择功能 (1-17): _'
    ];

    let lineIndex = 0;

    function displayNextLine() {
        if (lineIndex < outputLines.length) {
            const lineElement = document.createElement('div');
            lineElement.className = 'output-line';
            lineElement.textContent = outputLines[lineIndex];
            lineElement.style.animationDelay = `${lineIndex * 0.05}s`;
            terminalOutputElement.appendChild(lineElement);
            lineIndex++;
            setTimeout(displayNextLine, 100);
        }
    }

    displayNextLine();
}

// Start typing animation after page load
setTimeout(typeCommand, 1000);


// ========================================
// Smooth Scroll for Navigation Links
// ========================================
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            const offsetTop = target.offsetTop - 100;
            window.scrollTo({
                top: offsetTop,
                behavior: 'smooth'
            });
        }
    });
});


// ========================================
// Scroll-based Animations
// ========================================
function isElementInViewport(el) {
    const rect = el.getBoundingClientRect();
    return (
        rect.top >= 0 &&
        rect.left >= 0 &&
        rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) + 200 &&
        rect.right <= (window.innerWidth || document.documentElement.clientWidth)
    );
}

function handleScrollAnimations() {
    const animatedElements = document.querySelectorAll('.feature-card, .arch-layer, .step-item, .system-item');

    animatedElements.forEach((element, index) => {
        if (isElementInViewport(element) && !element.classList.contains('animated')) {
            setTimeout(() => {
                element.style.opacity = '0';
                element.style.transform = 'translateY(30px)';
                element.style.transition = 'opacity 0.6s ease-out, transform 0.6s ease-out';

                setTimeout(() => {
                    element.style.opacity = '1';
                    element.style.transform = 'translateY(0)';
                    element.classList.add('animated');
                }, 50);
            }, index * 100);
        }
    });
}

// Initial check
handleScrollAnimations();

// Check on scroll
let scrollTimeout;
window.addEventListener('scroll', () => {
    clearTimeout(scrollTimeout);
    scrollTimeout = setTimeout(handleScrollAnimations, 100);
});


// ========================================
// Code Copy Functionality
// ========================================
function copyCode(button, code) {
    // Create temporary textarea
    const textarea = document.createElement('textarea');
    textarea.value = code;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);

    // Select and copy
    textarea.select();
    textarea.setSelectionRange(0, 99999); // For mobile devices

    try {
        document.execCommand('copy');

        // Update button text
        const buttonText = button.querySelector('span');
        const originalText = buttonText.textContent;
        buttonText.textContent = '已复制!';

        // Reset after 2 seconds
        setTimeout(() => {
            buttonText.textContent = originalText;
        }, 2000);
    } catch (err) {
        console.error('复制失败:', err);
    }

    // Clean up
    document.body.removeChild(textarea);
}


// ========================================
// Navbar Scroll Effect
// ========================================
let lastScrollTop = 0;
const nav = document.querySelector('.nav');

window.addEventListener('scroll', () => {
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop;

    if (scrollTop > 100) {
        nav.style.background = 'rgba(10, 14, 39, 0.95)';
        nav.style.boxShadow = '0 10px 30px rgba(0, 0, 0, 0.3)';
    } else {
        nav.style.background = 'rgba(10, 14, 39, 0.8)';
        nav.style.boxShadow = 'none';
    }

    lastScrollTop = scrollTop;
});


// ========================================
// Parallax Effect for Background Orbs
// ========================================
window.addEventListener('scroll', () => {
    const scrolled = window.pageYOffset;
    const orb1 = document.querySelector('.orb-1');
    const orb2 = document.querySelector('.orb-2');

    if (orb1 && orb2) {
        orb1.style.transform = `translate(${scrolled * 0.1}px, ${scrolled * 0.15}px)`;
        orb2.style.transform = `translate(${-scrolled * 0.1}px, ${-scrolled * 0.1}px)`;
    }
});


// ========================================
// Stats Counter Animation
// ========================================
function animateCounter(element, target, duration = 2000) {
    let start = 0;
    const increment = target / (duration / 16); // 60fps
    const isDecimal = target.toString().includes('.');

    const timer = setInterval(() => {
        start += increment;
        if (start >= target) {
            element.textContent = formatNumber(target);
            clearInterval(timer);
        } else {
            element.textContent = formatNumber(Math.floor(start));
        }
    }, 16);
}

function formatNumber(num) {
    if (num >= 1000) {
        return (num / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
    }
    return num.toString();
}

// Trigger counter animation when stats are in view
let statsAnimated = false;

function checkStatsInView() {
    const statsSection = document.querySelector('.hero-stats');
    if (statsSection && isElementInViewport(statsSection) && !statsAnimated) {
        statsAnimated = true;

        const statValues = [
            { element: document.querySelectorAll('.stat-value')[0], target: 3800 },
            { element: document.querySelectorAll('.stat-value')[1], target: 17 },
            { element: document.querySelectorAll('.stat-value')[2], target: 5 },
            { element: document.querySelectorAll('.stat-value')[3], target: 4 }
        ];

        statValues.forEach(({ element, target }) => {
            if (element) {
                element.textContent = '0';
                setTimeout(() => {
                    animateCounter(element, target);
                }, 500);
            }
        });
    }
}

window.addEventListener('scroll', checkStatsInView);
window.addEventListener('load', checkStatsInView);


// ========================================
// Feature Card Hover Effects with Mouse Tracking
// ========================================
const featureCards = document.querySelectorAll('.feature-card');

featureCards.forEach(card => {
    card.addEventListener('mousemove', (e) => {
        const rect = card.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;

        const centerX = rect.width / 2;
        const centerY = rect.height / 2;

        const rotateX = (y - centerY) / 20;
        const rotateY = (centerX - x) / 20;

        card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-8px)`;
    });

    card.addEventListener('mouseleave', () => {
        card.style.transform = 'perspective(1000px) rotateX(0) rotateY(0) translateY(0)';
    });
});


// ========================================
// Mobile Menu Toggle (if needed)
// ========================================
// Add this if you want to implement a mobile hamburger menu
// For now, the navigation is kept simple


// ========================================
// Performance Optimization: Reduce Motion for Users Who Prefer It
// ========================================
if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.documentElement.style.setProperty('--transition-fast', '0s');
    document.documentElement.style.setProperty('--transition-normal', '0s');
    document.documentElement.style.setProperty('--transition-slow', '0s');
}


// ========================================
// Easter Egg: Console Message
// ========================================
console.log('%c🚀 Linux Setup.sh', 'font-size: 20px; font-weight: bold; color: #00f5ff;');
console.log('%c智能化的 Linux 服务器配置工具', 'font-size: 14px; color: #00ff9f;');
console.log('%cGitHub: https://github.com/SuperNG6/linux-setup.sh', 'font-size: 12px; color: #a8a6a3;');
console.log('%c\n感谢使用! 如果你发现任何问题，欢迎提交 Issue 😊', 'font-size: 12px; color: #6b6966;');
