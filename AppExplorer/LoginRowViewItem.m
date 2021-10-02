// Copyright (c) 2021 Simon Fell
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "LoginRowViewItem.h"
#import "credential.h"
#import "Defaults.h"

@interface LoginRowViewItem ()
@property (strong) IBOutlet NSButton *button;
@end

@implementation LoginRowViewItem

- (void)viewDidLoad {
    [super viewDidLoad];
    self.button.target = self;
    self.button.action = @selector(login:);
}

-(void)login:(id)sender {
    if (self.delegate) {
        [self.delegate credentialSelected:self.credential];
    }
}

-(NSString*)serverLabel {
    NSString *host = self.credential.server;
    if ([host caseInsensitiveCompare:LOGIN_LOGIN] == NSOrderedSame) {
        return @"Prod";
    }
    if ([host caseInsensitiveCompare:LOGIN_TEST] == NSOrderedSame) {
        return @"Sandbox";
    }
    NSURL *u = [NSURL URLWithString:host];
    return u.host;
}

@end
